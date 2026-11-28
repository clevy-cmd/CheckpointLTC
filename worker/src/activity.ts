import type { Caller, Env } from "./env";
import { json } from "./http";
import { requireRole } from "./access";
import { limits } from "./config";

export type ActivityKind =
  | "list.created"
  | "list.renamed"
  | "code.rotated"
  | "item.added"
  | "item.edited"
  | "item.checked"
  | "item.unchecked"
  | "item.deleted"
  | "item.restored"
  | "item.moved"
  | "comment.added"
  | "list.archived"
  | "list.unarchived"
  | "list.pinned"
  | "list.autoassign"
  | "item.split"
  | "list.imported"
  | "member.changed"
  | "report.approved"
  | "undo"
  | "member.added"
  | "member.removed"
  | "assignment.added"
  | "assignment.removed";

interface Entry {
  listId: string;
  actorId: number;
  kind: ActivityKind;
  itemId?: string | null;
  data?: Record<string, unknown> | null;
  onlyIfChanged?: boolean;
}

export function activityInsert(env: Env, entry: Entry): D1PreparedStatement {
  const guard = entry.onlyIfChanged ? "WHERE changes() > 0" : "";
  return env.DB.prepare(
    `INSERT INTO activity (list_id, revision, actor_id, kind, item_id, data, created_at)
     SELECT ?1, (SELECT revision FROM lists WHERE id = ?1), ?2, ?3, ?4, ?5, ?6 ${guard}`,
  ).bind(
    entry.listId,
    entry.actorId,
    entry.kind,
    entry.itemId ?? null,
    entry.data ? JSON.stringify(entry.data) : null,
    Date.now(),
  );
}

export function activityPrune(env: Env, listId: string): D1PreparedStatement {
  return env.DB.prepare(
    `DELETE FROM activity WHERE list_id = ?1 AND (created_at < ?2 OR id <=
       (SELECT id FROM activity WHERE list_id = ?1 ORDER BY id DESC LIMIT 1 OFFSET ?3))`,
  ).bind(listId, Date.now() - limits.activityMaxAgeMs, limits.activityPerList);
}

export function recordActivity(env: Env, entry: Entry): D1PreparedStatement[] {
  return [activityInsert(env, entry), activityPrune(env, entry.listId)];
}

interface ActivityRow {
  id: number;
  revision: number;
  actor_id: number;
  kind: ActivityKind;
  item_id: string | null;
  data: string | null;
  created_at: number;
}

export async function listActivity(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const { role } = await requireRole(env, listId, caller.userId, "editor");
  const afterParam = new URL(request.url).searchParams.get("after");
  const after = afterParam && /^\d{1,15}$/.test(afterParam) ? Number(afterParam) : 0;
  const count = role === "owner" ? limits.activityPerList : limits.editorActivityCount;
  const rows = await env.DB.prepare(
    `SELECT id, revision, actor_id, kind, item_id, data, created_at FROM activity
      WHERE list_id = ? AND id > ? ORDER BY id DESC LIMIT ?`,
  )
    .bind(listId, after, count)
    .all<ActivityRow>();
  return json({
    events: rows.results.map((r) => ({
      id: r.id,
      revision: r.revision,
      actorId: r.actor_id,
      kind: r.kind,
      itemId: r.item_id,
      data: r.data ? JSON.parse(r.data) : null,
      createdAt: r.created_at,
    })),
  });
}
