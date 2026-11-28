import type { Caller, Env } from "../env";
import { ApiError } from "../http";
import { bumpRevision, requireWritable } from "../access";
import { activityInsert, activityPrune } from "../activity";
import { limits } from "../config";
import { getListPayload } from "./lists";

const undoable = [
  "item.added",
  "item.deleted",
  "item.edited",
  "item.checked",
  "item.unchecked",
  "item.moved",
  "item.split",
  "list.renamed",
  "list.autoassign",
];

const columnFor: Record<string, string> = {
  text: "text",
  priority: "priority",
  dueAt: "due_at",
  label: "label",
  section: "section",
  notes: "notes",
  assigneeId: "assignee_id",
  assigneeIds: "assignees",
  link: "link",
};

interface EventRow {
  id: number;
  kind: string;
  item_id: string | null;
  data: string | null;
  created_at: number;
}

export async function undoLast(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireWritable(env, listId, caller.userId, "editor");
  const event = await env.DB.prepare(
    `SELECT id, kind, item_id, data, created_at FROM activity
      WHERE list_id = ? AND actor_id = ? AND undone = 0 AND created_at > ?
        AND kind IN (${undoable.map(() => "?").join(",")})
      ORDER BY id DESC LIMIT 1`,
  )
    .bind(listId, caller.userId, Date.now() - limits.trashMs, ...undoable)
    .first<EventRow>();
  if (!event) throw new ApiError("not_found", "There is nothing of yours to undo on this list.");

  const data = (event.data ? JSON.parse(event.data) : {}) as Record<string, unknown>;
  const now = Date.now();
  const revert: D1PreparedStatement[] = [];
  const item = event.item_id;

  switch (event.kind) {
    case "item.added":
      revert.push(env.DB.prepare("UPDATE items SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL").bind(now, item));
      break;
    case "item.deleted":
      revert.push(env.DB.prepare("UPDATE items SET deleted_at = NULL, updated_at = ? WHERE id = ?").bind(now, item));
      break;
    case "item.checked":
    case "item.unchecked":
      revert.push(
        env.DB.prepare("UPDATE items SET done = ?, version = version + 1, updated_at = ? WHERE id = ?").bind(
          event.kind === "item.checked" ? 0 : 1,
          now,
          item,
        ),
      );
      break;
    case "item.edited": {
      const changes = (data.changes ?? {}) as Record<string, { from: unknown }>;
      const keys = Object.keys(changes).filter((key) => columnFor[key]);
      if (keys.length === 0) throw new ApiError("not_found", "There is nothing of yours to undo on this list.");
      const sets = keys.map((key) => `${columnFor[key]} = ?`).join(", ");
      const values = keys.map((key) => {
        const from = changes[key].from;
        if (key === "assigneeIds") return Array.isArray(from) && from.length > 0 ? JSON.stringify(from) : null;
        return key === "link" && from !== null && from !== undefined ? JSON.stringify(from) : (from ?? null);
      });
      revert.push(
        env.DB.prepare(`UPDATE items SET ${sets}, version = version + 1, updated_at = ? WHERE id = ?`).bind(...values, now, item),
      );
      break;
    }
    case "item.moved": {
      const from = (data.from ?? {}) as { position?: number; section?: string | null };
      revert.push(
        env.DB.prepare("UPDATE items SET position = ?, section = ?, updated_at = ? WHERE id = ?").bind(
          from.position ?? 0,
          from.section ?? null,
          now,
          item,
        ),
      );
      break;
    }
    case "item.split": {
      const added = Array.isArray(data.added) ? data.added.filter((id): id is string => typeof id === "string").slice(0, 50) : [];
      revert.push(
        env.DB.prepare("UPDATE items SET text = ?, version = version + 1, updated_at = ? WHERE id = ?").bind(String(data.from ?? ""), now, item),
      );
      if (added.length > 0) {
        const marks = added.map(() => "?").join(",");
        revert.push(
          env.DB.prepare(`UPDATE items SET deleted_at = ? WHERE list_id = ? AND deleted_at IS NULL AND id IN (${marks})`).bind(now, listId, ...added),
          env.DB.prepare(`UPDATE activity SET undone = 1 WHERE list_id = ? AND kind = 'item.added' AND item_id IN (${marks})`).bind(listId, ...added),
        );
      }
      break;
    }
    case "list.autoassign": {
      const from = Array.isArray(data.from) ? data.from.filter((id): id is number => Number.isSafeInteger(id)) : [];
      revert.push(env.DB.prepare("UPDATE lists SET auto_assignees = ? WHERE id = ?").bind(from.length ? JSON.stringify(from) : null, listId));
      break;
    }
    case "list.renamed":
      revert.push(env.DB.prepare("UPDATE lists SET title = ? WHERE id = ?").bind(String(data.from ?? ""), listId));
      break;
  }

  await env.DB.batch([
    env.DB.prepare("UPDATE activity SET undone = 1 WHERE id = ?").bind(event.id),
    ...revert,
    bumpRevision(env, listId),
    activityInsert(env, {
      listId,
      actorId: caller.userId,
      kind: "undo",
      itemId: item,
      data: { of: event.kind, text: data.text ?? data.from ?? null },
    }),
    activityPrune(env, listId),
  ]);
  return getListPayload(env, listId, caller.userId);
}
