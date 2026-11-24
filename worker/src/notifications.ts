import type { Caller, Env } from "./env";
import { json, readBody } from "./http";
import { limits } from "./config";

export type NotificationKind = "task.assigned" | "comment.mention" | "list.shared";

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
      WHERE n.user_id = ? AND l.deleted_at IS NULL
      ORDER BY n.id DESC LIMIT ?`,
  )
    .bind(caller.userId, limits.notificationsMax)
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
  const upTo = typeof body.upTo === "number" && Number.isSafeInteger(body.upTo) ? body.upTo : Number.MAX_SAFE_INTEGER;
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare("UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL AND id <= ?").bind(now, caller.userId, upTo),
    env.DB.prepare(
      `DELETE FROM notifications WHERE user_id = ?1 AND id NOT IN
         (SELECT id FROM notifications WHERE user_id = ?1 ORDER BY id DESC LIMIT ?2)`,
    ).bind(caller.userId, limits.notificationsMax),
  ]);
  return json({ read: true });
}
