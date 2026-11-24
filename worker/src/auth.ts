import type { BanLevel, Caller, Env } from "./env";
import { ApiError } from "./http";
import { hashKey } from "./crypto";
import { bannedMessage, keyPrefix } from "./config";
import { isPaid } from "./oauth";
import { enforceLicence } from "./licence";
import { blocksLogin, endAllSessions } from "./sessions";

export async function authenticate(request: Request, env: Env): Promise<Caller> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer (\S+)$/.exec(header);
  const claimedId = Number(request.headers.get("x-roblox-user-id"));
  if (!match || !match[1].startsWith(keyPrefix) || !Number.isSafeInteger(claimedId) || claimedId <= 0) {
    throw new ApiError("unauthorized", "Sign in again from the plugin.");
  }
  const keyHash = await hashKey(match[1]);
  const row = await env.DB.prepare(
    `SELECT s.id AS session_id, s.last_seen_at AS session_seen_at,
            u.user_id, u.last_seen_at, u.roblox_refresh, u.licence_checked_at,
            (SELECT b.level FROM bans b WHERE b.user_id = u.user_id AND b.lifted_at IS NULL) AS ban_level
       FROM sessions s
       JOIN users u ON u.user_id = s.user_id
      WHERE s.key_hash = ?`,
  )
    .bind(keyHash)
    .first<{
      session_id: string;
      session_seen_at: number;
      user_id: number;
      last_seen_at: number;
      roblox_refresh: string | null;
      licence_checked_at: number | null;
      ban_level: BanLevel | null;
    }>();
  if (!row || row.user_id !== claimedId) throw new ApiError("unauthorized", "Sign in again from the plugin.");
  if (blocksLogin(row.ban_level)) {
    await env.DB.batch(endAllSessions(env, row.user_id));
    throw new ApiError("banned", bannedMessage);
  }
  if (isPaid(env)) await enforceLicence(env, row);

  const now = Date.now();
  const touches: D1PreparedStatement[] = [];
  if (now - row.session_seen_at > 3_600_000) {
    touches.push(env.DB.prepare("UPDATE sessions SET last_seen_at = ? WHERE id = ?").bind(now, row.session_id));
  }
  if (now - row.last_seen_at > 3_600_000) {
    touches.push(env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE user_id = ?").bind(now, row.user_id));
  }
  if (touches.length > 0) await env.DB.batch(touches);
  return { userId: row.user_id, sessionId: row.session_id, banLevel: row.ban_level };
}

export async function enforceRateLimit(limiter: RateLimit, key: string): Promise<void> {
  const { success } = await limiter.limit({ key });
  if (!success) throw new ApiError("rate_limited", "Too many requests. Slow down for a moment.");
}
