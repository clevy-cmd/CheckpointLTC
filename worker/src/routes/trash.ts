import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { bumpRevision, roleRank, resolveAccess } from "../access";
import { limits } from "../config";
import * as v from "../validate";
import { recordActivity } from "../activity";

const maxBatch = 200;

function ids(value: unknown, field: string): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new ApiError("bad_request", `${field} must be a list of ids.`);
  if (value.length > maxBatch) throw new ApiError("bad_request", `Up to ${maxBatch} at a time.`);
  return [...new Set(value.map((id) => v.idText(id, field)))];
}

async function trashedItem(env: Env, caller: Caller, itemId: string) {
  const item = await env.DB.prepare("SELECT id, list_id, text FROM items WHERE id = ? AND deleted_at IS NOT NULL")
    .bind(itemId)
    .first<{ id: string; list_id: string; text: string }>();
  if (!item) return null;
  const access = await resolveAccess(env, item.list_id, caller.userId);
  if (!access || roleRank[access.role] < roleRank.editor || access.list.archived_at !== null) return null;
  return { item, access };
}

async function trashedList(env: Env, caller: Caller, listId: string) {
  return env.DB.prepare("SELECT id FROM lists WHERE id = ? AND owner_id = ? AND deleted_at IS NOT NULL")
    .bind(listId, caller.userId)
    .first<{ id: string }>();
}

async function restoreAll(env: Env, caller: Caller, itemIds: string[], listIds: string[]) {
  let restored = 0;
  const skipped: string[] = [];
  for (const listId of listIds) {
    if (!(await trashedList(env, caller, listId))) {
      skipped.push(listId);
      continue;
    }
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM lists WHERE owner_id = ? AND deleted_at IS NULL")
      .bind(caller.userId)
      .first<{ n: number }>();
    if ((count?.n ?? 0) >= limits.listsPerOwner) {
      skipped.push(listId);
      continue;
    }
    await env.DB.prepare("UPDATE lists SET deleted_at = NULL, revision = revision + 1, updated_at = ? WHERE id = ?")
      .bind(Date.now(), listId)
      .run();
    restored++;
  }
  for (const itemId of itemIds) {
    const found = await trashedItem(env, caller, itemId);
    const list = found ? await env.DB.prepare("SELECT item_count FROM lists WHERE id = ?").bind(found.item.list_id).first<{ item_count: number }>() : null;
    if (!found || (list?.item_count ?? 0) >= limits.itemsPerList) {
      skipped.push(itemId);
      continue;
    }
    await env.DB.batch([
      env.DB.prepare("UPDATE items SET deleted_at = NULL, updated_by = ?, updated_at = ? WHERE id = ?").bind(caller.userId, Date.now(), itemId),
      bumpRevision(env, found.item.list_id),
      ...recordActivity(env, { listId: found.item.list_id, actorId: caller.userId, kind: "item.restored", itemId, data: { text: found.item.text } }),
    ]);
    restored++;
  }
  return { restored, skipped };
}

async function deleteAll(env: Env, caller: Caller, itemIds: string[], listIds: string[]) {
  let deleted = 0;
  const skipped: string[] = [];
  for (const listId of listIds) {
    const result = await env.DB.prepare("DELETE FROM lists WHERE id = ? AND owner_id = ? AND deleted_at IS NOT NULL")
      .bind(listId, caller.userId)
      .run();
    if (result.meta.changes === 0) skipped.push(listId);
    else deleted++;
  }
  for (const itemId of itemIds) {
    const found = await trashedItem(env, caller, itemId);
    if (!found) {
      skipped.push(itemId);
      continue;
    }
    await env.DB.prepare("DELETE FROM items WHERE id = ? AND deleted_at IS NOT NULL").bind(itemId).run();
    deleted++;
  }
  return { deleted, skipped };
}

export async function restoreSelected(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  return json(await restoreAll(env, caller, ids(body.items, "items"), ids(body.lists, "lists")));
}

export async function deleteSelected(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  return json(await deleteAll(env, caller, ids(body.items, "items"), ids(body.lists, "lists")));
}

export async function emptyTrash(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const [lists, items] = await env.DB.batch<{ id: string }>([
    env.DB.prepare("SELECT id FROM lists WHERE owner_id = ? AND deleted_at IS NOT NULL LIMIT ?").bind(caller.userId, maxBatch),
    env.DB.prepare(
      `SELECT i.id FROM items i JOIN lists l ON l.id = i.list_id
        WHERE i.deleted_at IS NOT NULL AND l.deleted_at IS NULL
          AND (l.owner_id = ?1 OR EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1 AND m.role IN ('admin', 'editor')))
        LIMIT ?2`,
    ).bind(caller.userId, maxBatch),
  ]);
  return json(await deleteAll(env, caller, items.results.map((r) => r.id), lists.results.map((r) => r.id)));
}
