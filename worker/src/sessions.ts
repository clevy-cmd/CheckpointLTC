import type { BanLevel, Caller, Env } from "./env";
import { ApiError, json } from "./http";
import { newId } from "./crypto";
import { defaultSessionLabel, limits } from "./config";

export function sessionLabel(value: unknown): string {
  if (typeof value !== "string") return defaultSessionLabel;
  const cleaned = value.replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, limits.sessionLabelMaxLength);
  return cleaned || defaultSessionLabel;
}

export function startSession(env: Env, userId: number, keyHash: string, label: string, now: number): D1PreparedStatement[] {
  return [
    env.DB.prepare(
      "INSERT INTO sessions (id, user_id, key_hash, label, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)",
    ).bind(newId(), userId, keyHash, label, now, now),
    env.DB.prepare(
      `DELETE FROM sessions WHERE user_id = ?1 AND id NOT IN
         (SELECT id FROM sessions WHERE user_id = ?1 ORDER BY created_at DESC LIMIT ?2)`,
    ).bind(userId, limits.sessionsPerUser),
  ];
}

export function endAllSessions(env: Env, userId: number): D1PreparedStatement[] {
  return [
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(userId),
    env.DB.prepare("UPDATE users SET key_hash = ? WHERE user_id = ?").bind(`revoked:${crypto.randomUUID()}`, userId),
  ];
}

export const blocksLogin = (level: BanLevel | null): boolean => level === "full" || level === "illegal";

export async function activeBan(env: Env, userId: number): Promise<BanLevel | null> {
  const row = await env.DB.prepare("SELECT level FROM bans WHERE user_id = ? AND lifted_at IS NULL")
    .bind(userId)
    .first<{ level: BanLevel }>();
  return row?.level ?? null;
}

export async function listSessions(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const rows = await env.DB.prepare(
    "SELECT id, label, created_at, last_seen_at FROM sessions WHERE user_id = ? ORDER BY last_seen_at DESC",
  )
    .bind(caller.userId)
    .all<{ id: string; label: string; created_at: number; last_seen_at: number }>();
  return json({
    sessions: rows.results.map((r) => ({
      id: r.id,
      label: r.label,
      createdAt: r.created_at,
      lastSeenAt: r.last_seen_at,
      current: r.id === caller.sessionId,
    })),
  });
}

export async function endCurrentSession(_request: Request, env: Env, caller: Caller): Promise<Response> {
  await env.DB.prepare("DELETE FROM sessions WHERE id = ?").bind(caller.sessionId).run();
  return json({ signedOut: true });
}

export async function endSession(_request: Request, env: Env, caller: Caller, sessionId: string): Promise<Response> {
  const result = await env.DB.prepare("DELETE FROM sessions WHERE id = ? AND user_id = ?")
    .bind(sessionId, caller.userId)
    .run();
  if (result.meta.changes !== 1) throw new ApiError("not_found", "That device is already signed out.");
  return json({ signedOut: true });
}
