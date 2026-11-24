import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { bumpRevision, requireRole, requireWritable } from "../access";
import { base64Url, hashKey, newId } from "../crypto";
import { limits } from "../config";
import * as v from "../validate";
import { recordActivity } from "../activity";
import { enforceRateLimit } from "../auth";

const gameKeyPrefix = "ltcg_";

export async function listGameKeys(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "admin");
  const rows = await env.DB.prepare("SELECT id, label, created_at FROM game_keys WHERE list_id = ? ORDER BY created_at ASC")
    .bind(listId)
    .all<{ id: string; label: string; created_at: number }>();
  return json({ keys: rows.results.map((r) => ({ id: r.id, label: r.label, createdAt: r.created_at })) });
}

export async function createGameKey(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireWritable(env, listId, caller.userId, "admin");
  const body = await readBody(request);
  const label = v.text(body.label ?? "My game", "Label", 40);
  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM game_keys WHERE list_id = ?").bind(listId).first<{ n: number }>();
  if ((count?.n ?? 0) >= limits.gameKeysPerList) throw new ApiError("limit_reached", `A list can have up to ${limits.gameKeysPerList} game keys.`);
  const key = gameKeyPrefix + base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const id = newId();
  await env.DB.prepare("INSERT INTO game_keys (id, list_id, owner_id, key_hash, label, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(id, listId, caller.userId, await hashKey(key), label, Date.now())
    .run();
  return json({ id, label, key, apiUrl: `${env.publicOrigin}/v1/game/reports` }, 201);
}

export async function deleteGameKey(_request: Request, env: Env, caller: Caller, listId: string, keyId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "admin");
  await env.DB.prepare("DELETE FROM game_keys WHERE id = ? AND list_id = ?").bind(keyId, listId).run();
  return json({ deleted: true });
}

export async function receiveGameReport(request: Request, env: Env): Promise<Response> {
  const key = request.headers.get("x-checkpoint-key") ?? "";
  if (!key.startsWith(gameKeyPrefix) || key.length > 80) throw new ApiError("unauthorized", "Missing or wrong game key.");
  const keyHash = await hashKey(key);
  await enforceRateLimit(env.gameLimiter, keyHash);
  const game = await env.DB.prepare(
    "SELECT g.id, g.list_id FROM game_keys g JOIN lists l ON l.id = g.list_id WHERE g.key_hash = ? AND l.deleted_at IS NULL",
  )
    .bind(keyHash)
    .first<{ id: string; list_id: string }>();
  if (!game) throw new ApiError("unauthorized", "Missing or wrong game key.");

  const body = await readBody(request);
  const kind = v.oneOf(body.kind, "kind", ["bug", "feedback"] as const);
  const text = v.text(body.text, "Report", limits.gameReportMaxLength);
  const playerId = v.userId(body.playerId, "playerId");
  const playerName = typeof body.playerName === "string" && /^[A-Za-z0-9_]{3,20}$/.test(body.playerName) ? body.playerName : String(playerId);
  const placeId = body.placeId === undefined || body.placeId === null || body.placeId === 0 ? null : v.userId(body.placeId, "placeId");
  if (body.filtered !== true) throw new ApiError("bad_request", "Run the text through TextService filtering on the server before sending.");

  const now = Date.now();
  const recent = await env.DB.prepare(
    `SELECT
       (SELECT MAX(created_at) FROM game_reports WHERE game_key_id = ?1 AND player_id = ?2) AS last_from_player,
       (SELECT COUNT(*) FROM game_reports WHERE game_key_id = ?1 AND created_at > ?3) AS last_hour`,
  )
    .bind(game.id, playerId, now - 3_600_000)
    .first<{ last_from_player: number | null; last_hour: number }>();
  if (recent?.last_from_player && now - recent.last_from_player < limits.gameReportCooldownMs) {
    throw new ApiError("cooldown", "Wait a minute before sending another report.", {
      retryAfterMs: limits.gameReportCooldownMs - (now - recent.last_from_player),
    });
  }
  if ((recent?.last_hour ?? 0) >= limits.gameReportsPerHour) throw new ApiError("rate_limited", "This game sent too many reports this hour.");

  const id = newId();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO game_reports (id, list_id, game_key_id, place_id, player_id, player_name, kind, text, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(id, game.list_id, game.id, placeId, playerId, playerName, kind, text, now),
    bumpRevision(env, game.list_id),
  ]);
  return json({ received: true, id }, 201);
}

export async function listReports(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "editor");
  const status = new URL(request.url).searchParams.get("status") === "all" ? null : "new";
  const rows = await env.DB.prepare(
    `SELECT id, place_id, player_id, player_name, kind, text, status, created_at FROM game_reports
      WHERE list_id = ? AND (?2 IS NULL OR status = ?2) ORDER BY created_at DESC LIMIT 200`,
  )
    .bind(listId, status)
    .all<{ id: string; place_id: number | null; player_id: number; player_name: string; kind: string; text: string; status: string; created_at: number }>();
  return json({
    reports: rows.results.map((r) => ({
      id: r.id,
      placeId: r.place_id,
      playerId: r.player_id,
      playerName: r.player_name,
      kind: r.kind,
      text: r.text,
      status: r.status,
      createdAt: r.created_at,
    })),
  });
}

async function loadReport(env: Env, caller: Caller, reportId: string) {
  const report = await env.DB.prepare("SELECT * FROM game_reports WHERE id = ?")
    .bind(reportId)
    .first<{ id: string; list_id: string; player_name: string; kind: string; text: string; status: string }>();
  if (!report) throw new ApiError("not_found", "That report is gone.");
  try {
    const access = await requireWritable(env, report.list_id, caller.userId, "editor");
    return { report, access };
  } catch (err) {
    if (err instanceof ApiError && err.code === "not_found") throw new ApiError("not_found", "That report is gone.");
    throw err;
  }
}

export async function approveReport(_request: Request, env: Env, caller: Caller, reportId: string): Promise<Response> {
  const { report, access } = await loadReport(env, caller, reportId);
  if (report.status !== "new") throw new ApiError("conflict", "That report was already handled.");
  if (access.list.item_count >= limits.itemsPerList) throw new ApiError("limit_reached", `A list can hold up to ${limits.itemsPerList} tasks.`);
  const top = await env.DB.prepare("SELECT COALESCE(MAX(position), 0) AS top FROM items WHERE list_id = ?").bind(report.list_id).first<{ top: number }>();
  const id = newId();
  const now = Date.now();
  const text = report.text.slice(0, limits.itemMaxLength);
  await env.DB.batch([
    env.DB.prepare("UPDATE game_reports SET status = 'approved' WHERE id = ? AND status = 'new'").bind(reportId),
    env.DB.prepare(
      `INSERT INTO items (id, list_id, text, done, position, version, label, section, notes, created_by, updated_by, created_at, updated_at)
       SELECT ?, ?, ?, 0, ?, 1, ?, 'Inbox', ?, ?, ?, ?, ? WHERE changes() > 0`,
    ).bind(
      id,
      report.list_id,
      text,
      (top?.top ?? 0) + 1,
      report.kind === "bug" ? "Bug" : null,
      `Reported in game by ${report.player_name}.${report.text.length > limits.itemMaxLength ? `\n\n${report.text}` : ""}`,
      caller.userId,
      caller.userId,
      now,
      now,
    ),
    bumpRevision(env, report.list_id),
    ...recordActivity(env, { listId: report.list_id, actorId: caller.userId, kind: "report.approved", itemId: id, data: { text } }),
  ]);
  return json({ approved: true, itemId: id });
}

export async function dismissReport(_request: Request, env: Env, caller: Caller, reportId: string): Promise<Response> {
  const { report } = await loadReport(env, caller, reportId);
  await env.DB.batch([
    env.DB.prepare("UPDATE game_reports SET status = 'dismissed' WHERE id = ?").bind(reportId),
    bumpRevision(env, report.list_id),
  ]);
  return json({ dismissed: true });
}
