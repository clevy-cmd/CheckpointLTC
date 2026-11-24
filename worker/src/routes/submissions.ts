import type { BanLevel, Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { newId, randomToken, hashKey } from "../crypto";
import { limits, uploadTypes } from "../config";
import * as v from "../validate";
import { assemble, fileKey, requireUploadsAllowed, type UploadRow } from "./uploads";
import { moderateImage, moderateText, moderateVideo, type Verdict } from "../moderation";
import { discordReady, postSubmission, reviewAlert, type SubmissionKind } from "../discord";
import { usersById } from "../users";

export async function cooldowns(env: Env, userId: number): Promise<Record<SubmissionKind, number>> {
  const rows = await env.DB.prepare(
    "SELECT kind, MAX(created_at) AS last FROM submissions WHERE user_id = ? AND created_at > ? GROUP BY kind",
  )
    .bind(userId, Date.now() - limits.submissionCooldownMs)
    .all<{ kind: SubmissionKind; last: number }>();
  const out: Record<SubmissionKind, number> = { bug: 0, feedback: 0 };
  for (const r of rows.results) out[r.kind] = r.last + limits.submissionCooldownMs;
  return out;
}

const rank: Record<BanLevel, number> = { upload: 1, full: 2, illegal: 3 };

export async function applyBan(env: Env, userId: number, level: BanLevel, reason: string, uploadId: string | null): Promise<void> {
  const current = await env.DB.prepare("SELECT level FROM bans WHERE user_id = ? AND lifted_at IS NULL")
    .bind(userId)
    .first<{ level: BanLevel }>();
  const now = Date.now();
  const statements = [
    env.DB.prepare("INSERT INTO strikes (user_id, upload_id, level, reason, created_at) VALUES (?, ?, ?, ?, ?)").bind(
      userId,
      uploadId,
      level,
      reason,
      now,
    ),
  ];
  if (!current || rank[level] > rank[current.level]) {
    statements.push(
      env.DB.prepare("UPDATE bans SET lifted_at = ? WHERE user_id = ? AND lifted_at IS NULL").bind(now, userId),
      env.DB.prepare("INSERT INTO bans (user_id, level, reason, created_at) VALUES (?, ?, ?, ?)").bind(userId, level, reason, now),
    );
    if (level !== "upload") {
      statements.push(env.DB.prepare("UPDATE users SET key_hash = ? WHERE user_id = ?").bind(`revoked:${crypto.randomUUID()}`, userId));
    }
  }
  await env.DB.batch(statements);
}

async function verdictFor(env: Env, upload: UploadRow, bytes: Uint8Array): Promise<Verdict> {
  const kind = uploadTypes[upload.extension].kind;
  if (kind === "image") return moderateImage(env, bytes);
  if (kind === "video") return moderateVideo(env, fileKey(upload.id));
  return moderateText(env, new TextDecoder().decode(bytes));
}

export async function submit(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  const kind = v.oneOf(body.kind, "kind", ["bug", "feedback"] as const);
  if (!discordReady(env, kind)) throw new ApiError("unavailable", "Reports are not set up on the server yet.");
  const title = v.text(body.title, "Title", limits.submissionTitleMaxLength);
  const text = v.optionalText(body.body, kind === "bug" ? "What happened" : "Your idea", limits.submissionBodyMaxLength);
  if (!text) throw new ApiError("bad_request", kind === "bug" ? "Tell me what happened." : "Tell me your idea or request.");
  const steps = kind === "bug" ? v.optionalText(body.steps ?? null, "Steps to reproduce", limits.submissionBodyMaxLength) : null;
  const category = kind === "feedback" && body.category != null ? v.oneOf(body.category, "category", ["UI", "Feature", "Other"] as const) : null;
  const includeInfo = body.includeInfo === true;
  const pluginVersion = includeInfo ? v.optionalText(request.headers.get("x-plugin-version") ?? null, "Plugin version", 20) : null;
  const studioInfo = includeInfo ? v.optionalText(body.studioInfo ?? null, "Studio info", 500) : null;
  const uploadId = body.uploadId === undefined || body.uploadId === null ? null : v.idText(body.uploadId, "uploadId");

  const ready = await cooldowns(env, caller.userId);
  if (ready[kind] > Date.now()) {
    const label = kind === "bug" ? "bug report" : "piece of feedback";
    throw new ApiError("cooldown", `You can send one ${label} per hour.`, { retryAt: ready[kind], retryAfterMs: ready[kind] - Date.now() });
  }

  let upload: UploadRow | null = null;
  if (uploadId) {
    requireUploadsAllowed(caller);
    upload = await env.DB.prepare("SELECT * FROM uploads WHERE id = ? AND user_id = ?").bind(uploadId, caller.userId).first<UploadRow>();
    if (!upload || upload.status !== "complete") throw new ApiError("bad_request", "That attachment did not finish uploading. Attach it again.");
  }

  const id = newId();
  const now = Date.now();
  const claimed = await env.DB.prepare(
    `INSERT INTO submissions (id, user_id, kind, title, body, extra, attachment_id, status, created_at)
     SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, 'sending', ?8
      WHERE NOT EXISTS (SELECT 1 FROM submissions WHERE user_id = ?2 AND kind = ?3 AND created_at > ?9)`,
  )
    .bind(id, caller.userId, kind, title, text, JSON.stringify({ steps, category, pluginVersion, studioInfo }), uploadId, now, now - limits.submissionCooldownMs)
    .run();
  if (claimed.meta.changes !== 1) throw new ApiError("cooldown", "You can send one per hour.", { retryAt: now + limits.submissionCooldownMs });

  let attachment: { name: string; bytes: Uint8Array; mime: string } | null = null;
  let heldReviewUrl: string | null = null;
  let attachmentStatus: string | null = null;
  try {
    if (upload) {
      const bytes = await assemble(env, upload);
      const verdict = await verdictFor(env, upload, bytes);
      if (verdict.status === "clean") {
        attachment = { name: upload.name, bytes, mime: uploadTypes[upload.extension].mime };
        attachmentStatus = "clean";
      } else {
        const token = randomToken();
        heldReviewUrl = `${env.publicOrigin}/review/${token}`;
        attachmentStatus = "held";
        await env.DB.prepare(
          "UPDATE uploads SET status = 'held', verdict = ?, scores = ?, review_hash = ?, expires_at = ? WHERE id = ?",
        )
          .bind(verdict.reason, JSON.stringify(verdict.scores), await hashKey(token), Date.now() + limits.heldUploadMs, upload.id)
          .run();
      }
    }

    const names = await usersById(env, [caller.userId]);
    const who = names.get(caller.userId);
    const { threadId } = await postSubmission(env, {
      kind,
      userId: caller.userId,
      username: who?.name ?? String(caller.userId),
      displayName: who?.displayName ?? "",
      title,
      body: text,
      steps,
      category,
      pluginVersion,
      studioInfo,
      attachment,
      heldReviewUrl,
    });
    await env.DB.prepare("UPDATE submissions SET status = 'sent', thread_id = ? WHERE id = ?").bind(threadId, id).run();
    if (heldReviewUrl && upload) {
      await reviewAlert(
        env,
        `Attachment held for review on a ${kind === "bug" ? "bug report" : "feedback"} post "${title}" from @${who?.name ?? caller.userId} (${caller.userId}). File ${upload.name}. Review it here: ${heldReviewUrl}`,
      );
    }
    if (upload && attachmentStatus === "clean") {
      await env.UPLOADS.delete(fileKey(upload.id));
      await env.DB.prepare("UPDATE uploads SET status = 'sent', expires_at = NULL WHERE id = ?").bind(upload.id).run();
    }
  } catch (err) {
    await env.DB.prepare("DELETE FROM submissions WHERE id = ?").bind(id).run();
    if (upload && attachmentStatus !== "held") {
      await env.UPLOADS.delete(fileKey(upload.id));
      await env.DB.prepare("DELETE FROM uploads WHERE id = ?").bind(upload.id).run();
    }
    throw err;
  }

  return json(
    {
      sent: true,
      attachment: attachmentStatus,
      nextAllowedAt: Date.now() + limits.submissionCooldownMs,
      message: attachmentStatus === "held" ? "Sent. Your attachment is waiting for a manual check first." : "Sent. Thanks!",
      ...(env.environmentName === "local" && heldReviewUrl ? { reviewUrl: heldReviewUrl } : {}),
    },
    201,
  );
}
