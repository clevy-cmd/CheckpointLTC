import type { Env } from "./env";
import { limits } from "./config";
import { discardParts, fileKey } from "./routes/uploads";

export async function cleanup(env: Env): Promise<void> {
  const now = Date.now();
  const trashCutoff = now - limits.trashMs;

  const expired = await env.DB.prepare(
    "SELECT id, parts, status FROM uploads WHERE keep = 0 AND expires_at IS NOT NULL AND expires_at < ? LIMIT 200",
  )
    .bind(now)
    .all<{ id: string; parts: number; status: string }>();
  for (const upload of expired.results) {
    if (upload.status === "pending" || upload.status === "complete") await discardParts(env, upload.id, upload.parts);
    await env.UPLOADS.delete(fileKey(upload.id));
    await env.DB.prepare("UPDATE uploads SET status = 'rejected', review_hash = NULL, expires_at = NULL WHERE id = ?")
      .bind(upload.id)
      .run();
  }

  await env.DB.batch([
    env.DB.prepare("DELETE FROM items WHERE deleted_at IS NOT NULL AND deleted_at < ?").bind(trashCutoff),
    env.DB.prepare("DELETE FROM lists WHERE deleted_at IS NOT NULL AND deleted_at < ?").bind(trashCutoff),
    env.DB.prepare("DELETE FROM presence WHERE updated_at < ?").bind(now - limits.presenceTtlMs * 10),
    env.DB.prepare("DELETE FROM export_tokens WHERE expires_at < ?").bind(now),
    env.DB.prepare("DELETE FROM game_report_attempts WHERE created_at < ?").bind(now - limits.gameAttemptsKeptMs),
    env.DB.prepare("DELETE FROM game_keys WHERE revoked_at IS NOT NULL AND revoked_at < ?").bind(now - limits.activityMaxAgeMs),
    env.DB.prepare("DELETE FROM login_sessions WHERE expires_at < ?").bind(now),
    env.DB.prepare("DELETE FROM activity WHERE created_at < ?").bind(now - limits.activityMaxAgeMs),
    env.DB.prepare("DELETE FROM game_reports WHERE status <> 'new' AND created_at < ?").bind(now - limits.activityMaxAgeMs),
    env.DB.prepare("DELETE FROM notifications WHERE created_at < ?").bind(now - limits.notificationMaxAgeMs),
    env.DB.prepare("DELETE FROM submissions WHERE created_at < ? AND attachment_id IS NULL").bind(now - limits.activityMaxAgeMs),
  ]);
}
