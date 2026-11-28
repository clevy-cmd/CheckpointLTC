import type { Caller, Env } from "./env";
import { json, readBody } from "./http";
import { limits } from "./config";

export type NotificationKind = "task.assigned" | "comment.mention" | "list.shared" | "gamekey.revoked";

export function notify(
  env: Env,
  userId: number,
  listId: string,
  itemId: string | null,
  actorId: number,
  kind: NotificationKind,
  data: Record<string, unknown>,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO notifications (user_id, list_id, item_id, actor_id, kind, data, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(userId, listId, itemId, actorId, kind, JSON.stringify(data), Date.now());
}

export async function listNotifications(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT n.id, n.list_id, n.item_id, n.actor_id, n.kind, n.data, n.created_at, n.read_at, l.title AS list_title
       FROM notifications n JOIN lists l ON l.id = n.list_id
      WHERE n.user_id = ? AND l.deleted_at IS NULL AND n.deleted_at IS NULL AND n.created_at > ?
      ORDER BY n.id DESC LIMIT ?`,
  )
    .bind(caller.userId, Date.now() - limits.notificationMaxAgeMs, limits.notificationsMax)
    .all<{
      id: number;
      list_id: string;
      item_id: string | null;
      actor_id: number;
      kind: NotificationKind;
      data: string | null;
      created_at: number;
      read_at: number | null;
      list_title: string;
    }>();
  return json({
    notifications: rows.results.map((r) => ({
      id: r.id,
      listId: r.list_id,
      listTitle: r.list_title,
      itemId: r.item_id,
      actorId: r.actor_id,
      kind: r.kind,
      data: r.data ? JSON.parse(r.data) : null,
      createdAt: r.created_at,
      read: r.read_at !== null,
    })),
    unread: rows.results.filter((r) => r.read_at === null).length,
  });
}

export async function readNotifications(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  const now = Date.now();
  const ids = Array.isArray(body.ids)
    ? [...new Set(body.ids.filter((id): id is number => typeof id === "number" && Number.isSafeInteger(id)))].slice(0, limits.notificationsMax)
    : null;
  const upTo = typeof body.upTo === "number" && Number.isSafeInteger(body.upTo) ? body.upTo : Number.MAX_SAFE_INTEGER;
  const mark =
    ids === null
      ? env.DB.prepare("UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL AND id <= ?").bind(now, caller.userId, upTo)
      : env.DB.prepare(
          `UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL AND id IN (SELECT value FROM json_each(?))`,
        ).bind(now, caller.userId, JSON.stringify(ids));
  if (ids !== null && ids.length === 0) return json({ read: true });
  await env.DB.batch([
    mark,
    env.DB.prepare(
      `DELETE FROM notifications WHERE user_id = ?1 AND id NOT IN
         (SELECT id FROM notifications WHERE user_id = ?1 ORDER BY id DESC LIMIT ?2)`,
    ).bind(caller.userId, limits.notificationsMax),
  ]);
  return json({ read: true });
}

export function notificationIds(value: unknown): number[] {
  return Array.isArray(value)
    ? [...new Set(value.filter((id): id is number => typeof id === "number" && Number.isSafeInteger(id)))].slice(0, limits.notificationsMax)
    : [];
}

export async function restoreNotifications(env: Env, userId: number, ids: number[]): Promise<number> {
  if (ids.length === 0) return 0;
  const result = await env.DB.prepare(
    "UPDATE notifications SET deleted_at = NULL WHERE user_id = ? AND deleted_at IS NOT NULL AND id IN (SELECT value FROM json_each(?))",
  )
    .bind(userId, JSON.stringify(ids))
    .run();
  return result.meta.changes;
}

export async function eraseNotifications(env: Env, userId: number, ids: number[] | "all"): Promise<number> {
  const result =
    ids === "all"
      ? await env.DB.prepare("DELETE FROM notifications WHERE user_id = ? AND deleted_at IS NOT NULL").bind(userId).run()
      : ids.length === 0
        ? null
        : await env.DB.prepare(
            "DELETE FROM notifications WHERE user_id = ? AND deleted_at IS NOT NULL AND id IN (SELECT value FROM json_each(?))",
          )
            .bind(userId, JSON.stringify(ids))
            .run();
  return result?.meta.changes ?? 0;
}

export async function deleteNotifications(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  const ids = notificationIds(body.ids);
  if (ids.length === 0) return json({ deleted: 0 });
  const result = await env.DB.prepare(
    `UPDATE notifications SET deleted_at = ? WHERE user_id = ? AND deleted_at IS NULL AND id IN (SELECT value FROM json_each(?))
       AND NOT (kind = 'gamekey.revoked' AND read_at IS NULL)`,
  )
    .bind(Date.now(), caller.userId, JSON.stringify(ids))
    .run();
  return json({ deleted: result.meta.changes });
}
