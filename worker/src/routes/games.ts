import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { bumpRevision, requireRole, requireWritable } from "../access";
import { base64Url, hashKey, newId } from "../crypto";
import { limits } from "../config";
import * as v from "../validate";
import { recordActivity } from "../activity";
import { enforceRateLimit } from "../auth";
import { notify } from "../notifications";
import { detailAlert } from "../discord";
import { usersById, type PublicUser } from "../users";

const gameKeyPrefix = "ltcg_";

export async function listGameKeys(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "admin");
  const rows = await env.DB.prepare(
    "SELECT id, label, created_at, revoked_at, revoked_reason FROM game_keys WHERE list_id = ? ORDER BY created_at ASC",
  )
    .bind(listId)
    .all<{ id: string; label: string; created_at: number; revoked_at: number | null; revoked_reason: string | null }>();
  return json({
    keys: rows.results.map((r) => ({
      id: r.id,
      label: r.label,
      createdAt: r.created_at,
      revokedAt: r.revoked_at,
      revokedReason: r.revoked_reason,
    })),
  });
}

export async function createGameKey(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireWritable(env, listId, caller.userId, "admin");
  const body = await readBody(request);
  const label = v.text(body.label ?? "My game", "Label", 40);
  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM game_keys WHERE list_id = ? AND revoked_at IS NULL").bind(listId).first<{ n: number }>();
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

const floodFallback = { count: 5, windowMs: 5 * 60 * 1000 };

function floodRule(env: Env): { count: number; windowMs: number } {
  const match = /^(\d{1,4})\/(\d{1,5})$/.exec(env.GAME_FLOOD_RULE?.trim() ?? "");
  if (!match) return floodFallback;
  const count = Number(match[1]);
  const windowMs = Math.min(Number(match[2]) * 1000, limits.gameAttemptsKeptMs);
  return count > 0 && windowMs > 0 ? { count, windowMs } : floodFallback;
}

const keyTurnedOff = () =>
  new ApiError("unauthorized", "This game key was turned off. Make a new one in the CheckpointLTC plugin.", { revoked: true });

type GameKeyRow = { id: string; list_id: string; owner_id: number; label: string; created_at: number; revoked_at: number | null };

function floodSource(request: Request, body: Record<string, unknown>) {
  const cf = (request as { cf?: Record<string, unknown> }).cf ?? {};
  return {
    ip: request.headers.get("cf-connecting-ip") ?? "unknown",
    country: typeof cf.country === "string" ? cf.country : null,
    city: typeof cf.city === "string" ? cf.city : null,
    asn: typeof cf.asn === "number" ? cf.asn : null,
    network: typeof cf.asOrganization === "string" ? cf.asOrganization : null,
    userAgent: (request.headers.get("user-agent") ?? "").slice(0, 200) || null,
    robloxIdHeader: request.headers.get("roblox-id"),
    claimedPlaceId: typeof body.placeId === "number" ? body.placeId : null,
    claimedPlayerName: typeof body.playerName === "string" ? body.playerName.slice(0, 40) : null,
  };
}

const when = (ms: number | null | undefined) => (ms ? `<t:${Math.floor(ms / 1000)}:F>` : "never");
const profile = (id: number) => `https://www.roblox.com/users/${id}/profile`;

async function revokeForFlood(
  env: Env,
  game: GameKeyRow,
  playerId: number,
  kind: string,
  tries: number,
  rule: { count: number; windowMs: number },
  source: ReturnType<typeof floodSource>,
): Promise<void> {
  const now = Date.now();
  const done = await env.DB.prepare(
    "UPDATE game_keys SET revoked_at = ?, revoked_reason = 'flood', revoked_detail = ? WHERE id = ? AND revoked_at IS NULL",
  )
    .bind(now, JSON.stringify({ playerId, kind, tries, ...source }), game.id)
    .run();
  if (done.meta.changes !== 1) return;

  const list = await env.DB.prepare("SELECT title, owner_id FROM lists WHERE id = ?").bind(game.list_id).first<{ title: string; owner_id: number }>();
  const admins = await env.DB.prepare("SELECT user_id FROM members WHERE list_id = ? AND role = 'admin'")
    .bind(game.list_id)
    .all<{ user_id: number }>();
  const adminIds = admins.results.map((a) => a.user_id);
  const listOwner = list?.owner_id ?? game.owner_id;
  const told = [...new Set([listOwner, ...adminIds])];

  await env.DB.batch([
    ...told.map((id) => notify(env, id, game.list_id, null, game.owner_id, "gamekey.revoked", { label: game.label, reason: "flood" })),
    bumpRevision(env, game.list_id),
  ]);

  const names = await usersById(env, [game.owner_id, listOwner, playerId, ...adminIds]).catch(() => new Map<number, PublicUser>());
  const account = await env.DB.prepare("SELECT created_at, last_seen_at FROM users WHERE user_id = ?")
    .bind(game.owner_id)
    .first<{ created_at: number; last_seen_at: number | null }>();
  const who = (id: number) => {
    const u = names.get(id);
    return u ? `**${u.displayName}** (@${u.name}) · \`${id}\`\n${profile(id)}` : `\`${id}\`\n${profile(id)}`;
  };

  await detailAlert(
    env,
    "Game key shut off: possible leaked key",
    `Key **${game.label}** got ${tries} ${kind} report tries from one player inside ${Math.round(rule.windowMs / 1000)} seconds, so it was turned off. ` +
      `The key belongs to the owner below. Whoever has it now sent the flood from the source below.`,
    [
      { name: "Key owner (made the key)", value: who(game.owner_id) },
      { name: "Key owner on CheckpointLTC", value: `Joined ${when(account?.created_at)}\nLast seen ${when(account?.last_seen_at)}` },
      { name: "List", value: `**${list?.title ?? "unknown"}** · \`${game.list_id}\``, inline: true },
      { name: "Key", value: `**${game.label}** · \`${game.id}\`\nMade ${when(game.created_at)}`, inline: true },
      { name: "List owner", value: listOwner === game.owner_id ? "Same as key owner" : who(listOwner) },
      { name: "List admins", value: adminIds.length ? adminIds.map(who).join("\n") : "None" },
      {
        name: "Flood came from",
        value: [
          `IP \`${source.ip}\``,
          `${source.city ?? "?"}, ${source.country ?? "?"}`,
          `Network ${source.network ?? "?"} (AS${source.asn ?? "?"})`,
          `User agent \`${source.userAgent ?? "none"}\``,
          `Roblox-Id header ${source.robloxIdHeader ? `\`${source.robloxIdHeader}\` (looks like a real game server)` : "missing (not sent from a Roblox server)"}`,
        ].join("\n"),
      },
      {
        name: "Claimed player (can be faked)",
        value: `${who(playerId)}\nName sent: ${source.claimedPlayerName ?? "none"} · Place sent: ${source.claimedPlaceId ?? "none"}`,
      },
    ],
  );
}

export async function receiveGameReport(request: Request, env: Env): Promise<Response> {
  await enforceRateLimit(env.gameIpLimiter, request.headers.get("cf-connecting-ip") ?? "unknown");
  const key = request.headers.get("x-checkpoint-key") ?? "";
  if (!key.startsWith(gameKeyPrefix) || key.length > 80) throw new ApiError("unauthorized", "Missing or wrong game key.");
  const keyHash = await hashKey(key);
  await enforceRateLimit(env.gameLimiter, keyHash);
  const game = await env.DB.prepare(
    `SELECT g.id, g.list_id, g.owner_id, g.label, g.created_at, g.revoked_at FROM game_keys g JOIN lists l ON l.id = g.list_id
      WHERE g.key_hash = ? AND l.deleted_at IS NULL`,
  )
    .bind(keyHash)
    .first<GameKeyRow>();
  if (!game) throw new ApiError("unauthorized", "Missing or wrong game key.");
  if (game.revoked_at) throw keyTurnedOff();

  const body = await readBody(request);
  const kind = v.oneOf(body.kind, "kind", ["bug", "feedback"] as const);
  const playerId = v.userId(body.playerId, "playerId");

  const now = Date.now();
  const rule = floodRule(env);
  const [, tries] = await env.DB.batch<{ n: number }>([
    env.DB.prepare("INSERT INTO game_report_attempts (game_key_id, player_id, kind, created_at) VALUES (?, ?, ?, ?)").bind(
      game.id,
      playerId,
      kind,
      now,
    ),
    env.DB.prepare(
      "SELECT COUNT(*) AS n FROM game_report_attempts WHERE game_key_id = ? AND player_id = ? AND kind = ? AND created_at > ?",
    ).bind(game.id, playerId, kind, now - rule.windowMs),
  ]);
  if ((tries.results[0]?.n ?? 0) > rule.count) {
    await revokeForFlood(env, game, playerId, kind, tries.results[0]?.n ?? 0, rule, floodSource(request, body));
    throw keyTurnedOff();
  }

  const text = v.text(body.text, "Report", limits.gameReportMaxLength);
  const playerName = typeof body.playerName === "string" && /^[A-Za-z0-9_]{3,20}$/.test(body.playerName) ? body.playerName : String(playerId);
  const placeId = body.placeId === undefined || body.placeId === null || body.placeId === 0 ? null : v.userId(body.placeId, "placeId");
  if (body.filtered !== true) throw new ApiError("bad_request", "Run the text through TextService filtering on the server before sending.");

  const recent = await env.DB.prepare(
    `SELECT
       (SELECT MAX(created_at) FROM game_reports WHERE game_key_id = ?1 AND player_id = ?2) AS last_from_player,
       (SELECT COUNT(*) FROM game_reports WHERE game_key_id = ?1 AND created_at > ?3) AS last_hour,
       (SELECT COUNT(*) FROM game_reports WHERE list_id = ?4 AND status = 'new') AS waiting`,
  )
    .bind(game.id, playerId, now - 3_600_000, game.list_id)
    .first<{ last_from_player: number | null; last_hour: number; waiting: number }>();
  if (recent?.last_from_player && now - recent.last_from_player < limits.gameReportCooldownMs) {
    throw new ApiError("cooldown", "One report per player per hour.", {
      retryAfterMs: limits.gameReportCooldownMs - (now - recent.last_from_player),
    });
  }
  if ((recent?.last_hour ?? 0) >= limits.gameReportsPerHour) throw new ApiError("rate_limited", "This game sent too many reports this hour.");
  if ((recent?.waiting ?? 0) >= limits.gameReportsWaiting) {
    throw new ApiError("rate_limited", "This list's report inbox is full. Approve or dismiss some first.");
  }

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
