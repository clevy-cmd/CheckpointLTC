import type { Env } from "../env";
import { hashKey } from "../crypto";
import { uploadTypes } from "../config";
import { escapeHtml, messagePage, page } from "../pages";
import { fileKey, type UploadRow } from "./uploads";
import { postToThread, urgentAlert, type SubmissionKind } from "../discord";
import { applyBan } from "./submissions";

interface HeldRow extends UploadRow {
  kind: SubmissionKind;
  title: string;
  thread_id: string | null;
}

async function findHeld(env: Env, token: string): Promise<HeldRow | null> {
  if (!/^[A-Za-z0-9_-]{30,60}$/.test(token)) return null;
  return env.DB.prepare(
    `SELECT u.*, s.kind, s.title, s.thread_id FROM uploads u JOIN submissions s ON s.attachment_id = u.id
      WHERE u.review_hash = ? AND u.status IN ('held', 'evidence')`,
  )
    .bind(await hashKey(token))
    .first<HeldRow>();
}

function sameText(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export async function reviewFile(_request: Request, env: Env, token: string): Promise<Response> {
  const held = await findHeld(env, token);
  if (!held) return new Response("Not found", { status: 404 });
  const object = await env.UPLOADS.get(fileKey(held.id));
  if (!object) return new Response("Not found", { status: 404 });
  return new Response(object.body, {
    headers: {
      "content-type": uploadTypes[held.extension].kind === "text" ? "text/plain; charset=utf-8" : uploadTypes[held.extension].mime,
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'; sandbox",
      "x-robots-tag": "noindex",
    },
  });
}

export async function reviewPage(_request: Request, env: Env, token: string): Promise<Response> {
  const held = await findHeld(env, token);
  if (!held) return messagePage("Nothing to review", "This file was already reviewed or has expired.", false, 404);
  const kind = uploadTypes[held.extension].kind;
  const src = `/review/${token}/file`;
  const object = kind === "text" ? await env.UPLOADS.get(fileKey(held.id)) : null;
  const preview =
    kind === "image"
      ? `<img src="${src}" alt="Held attachment">`
      : kind === "video"
        ? `<video controls preload="metadata" src="${src}"></video>`
        : `<pre>${escapeHtml(object ? (await object.text()).slice(0, 20000) : "")}</pre>`;
  const ready = Boolean(env.REVIEW_PASSWORD);
  return page(
    "Review attachment",
    `<h1>Attachment held for review</h1>
<p><b>${escapeHtml(held.title)}</b> from UserId ${held.user_id}. File ${escapeHtml(held.name)}, ${(held.size / 1024 / 1024).toFixed(1)} MB.</p>
<p>Why it was held: ${escapeHtml(held.verdict ?? "Not checked")}.${held.status === "evidence" ? " <b>This file is preserved as evidence.</b>" : ""}</p>
<div class="preview">${preview}</div>
${
  ready && held.status === "held"
    ? `<form class="review" method="post">
<input type="password" name="password" placeholder="Review password" autocomplete="current-password" required>
<button name="action" value="approve">Approve and post it</button>
<button name="action" value="reject">Reject, no strike</button>
<button class="danger" name="action" value="strike">Reject and strike (upload ban)</button>
<button class="danger" name="action" value="severe">Reject and ban from CheckpointLTC</button>
<button class="danger" name="action" value="illegal">Illegal content: ban, keep evidence, alert</button>
</form>`
    : ready
      ? ""
      : `<p class="bad">Set the REVIEW_PASSWORD Worker secret to approve or reject from here.</p>`
}
<small>Held files delete on their own 7 days after upload unless kept as evidence.</small>`,
    200,
    true,
  );
}

export async function reviewAction(request: Request, env: Env, token: string): Promise<Response> {
  const held = await findHeld(env, token);
  if (!held || held.status !== "held") return messagePage("Nothing to review", "This file was already reviewed or has expired.", false, 404);
  const form = await request.formData();
  const password = String(form.get("password") ?? "");
  const action = String(form.get("action") ?? "");
  if (!env.REVIEW_PASSWORD || !sameText(password, env.REVIEW_PASSWORD)) {
    return messagePage("Wrong password", "Go back and try again.", true, 403);
  }

  const key = fileKey(held.id);
  if (action === "approve") {
    const object = await env.UPLOADS.get(key);
    if (object && held.thread_id) {
      await postToThread(env, held.kind, held.thread_id, "Attachment approved after review.", {
        name: held.name,
        bytes: new Uint8Array(await object.arrayBuffer()),
        mime: uploadTypes[held.extension].mime,
      });
    }
    await env.UPLOADS.delete(key);
    await env.DB.prepare("UPDATE uploads SET status = 'sent', review_hash = NULL, expires_at = NULL WHERE id = ?").bind(held.id).run();
    return messagePage("Approved", "The attachment was posted to the report.", false);
  }

  if (action === "illegal") {
    await env.DB.prepare("UPDATE uploads SET status = 'evidence', keep = 1, expires_at = NULL WHERE id = ?").bind(held.id).run();
    await applyBan(env, held.user_id, "illegal", "Illegal content in an upload", held.id);
    await urgentAlert(
      env,
      `UserId ${held.user_id} uploaded content marked illegal (upload ${held.id}, ${held.name}). The file is preserved in R2 at ${key}. ` +
        "Report it to the authorities (NCMEC CyberTipline for child sexual abuse material: https://report.cybertip.org).",
    );
    if (held.thread_id) await postToThread(env, held.kind, held.thread_id, "Attachment removed after review.", null).catch(() => undefined);
    return messagePage("Banned and preserved", "The account is banned, the file is kept privately as evidence, and an urgent alert was sent.", false);
  }

  if (action === "reject" || action === "strike" || action === "severe") {
    await env.UPLOADS.delete(key);
    await env.DB.prepare("UPDATE uploads SET status = 'rejected', review_hash = NULL, expires_at = NULL WHERE id = ?").bind(held.id).run();
    if (action === "strike") await applyBan(env, held.user_id, "upload", "Inappropriate upload", held.id);
    if (action === "severe") await applyBan(env, held.user_id, "full", "Severe violation in an upload", held.id);
    if (held.thread_id) await postToThread(env, held.kind, held.thread_id, "Attachment removed after review.", null).catch(() => undefined);
    const note = action === "strike" ? " The account got a strike and can no longer upload." : action === "severe" ? " The account is banned." : "";
    return messagePage("Rejected", `The file was deleted.${note}`, false);
  }
  return messagePage("Unknown action", "Go back and pick one of the buttons.", true, 400);
}
