import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { bumpRevision, bumpRevisionIfChanged, requireRole, requireWritable, roleRank, type Access } from "../access";
import { getListPayload } from "./lists";
import { newId } from "../crypto";
import { labels, limits } from "../config";
import * as v from "../validate";
import { activityInsert, activityPrune, recordActivity } from "../activity";
import { notify } from "../notifications";

export interface ItemRow {
  id: string;
  list_id: string;
  text: string;
  done: number;
  position: number;
  version: number;
  priority: number;
  due_at: number | null;
  label: string | null;
  section: string | null;
  notes: string | null;
  assignee_id: number | null;
  assignees: string | null;
  link: string | null;
  created_by: number;
  updated_by: number;
  created_at: number;
  updated_at: number;
  deleted_at: number | null;
}

export function parseIdList(raw: string | null): number[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? parsed.filter((id): id is number => Number.isSafeInteger(id) && id > 0) : [];
  } catch {
    return [];
  }
}

export function assigneesOf(r: { assignees: string | null; assignee_id: number | null }): number[] {
  if (r.assignees) return parseIdList(r.assignees);
  return r.assignee_id ? [r.assignee_id] : [];
}

export function itemJson(r: ItemRow) {
  return {
    id: r.id,
    listId: r.list_id,
    text: r.text,
    done: r.done === 1,
    position: r.position,
    version: r.version,
    priority: r.priority,
    dueAt: r.due_at,
    label: r.label,
    section: r.section,
    notes: r.notes,
    assigneeId: r.assignee_id,
    assigneeIds: assigneesOf(r),
    link: r.link ? JSON.parse(r.link) : null,
    createdBy: r.created_by,
    updatedBy: r.updated_by,
    updatedAt: r.updated_at,
  };
}

const itemGone = () => new ApiError("not_found", "That task was deleted or you no longer have access.");

export async function loadItem(env: Env, itemId: string, includeDeleted = false): Promise<ItemRow> {
  const row = await env.DB.prepare(
    `SELECT * FROM items WHERE id = ? ${includeDeleted ? "" : "AND deleted_at IS NULL"}`,
  )
    .bind(itemId)
    .first<ItemRow>();
  if (!row) throw itemGone();
  return row;
}

async function hidden<T>(work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (err) {
    if (err instanceof ApiError && err.code === "not_found") throw itemGone();
    throw err;
  }
}

async function onListAlready(env: Env, access: Access, targets: number[]): Promise<Set<number>> {
  const others = [...new Set(targets)].filter((id) => id !== access.list.owner_id);
  const ok = new Set<number>([access.list.owner_id]);
  if (others.length === 0) return ok;
  const rows = await env.DB.prepare(
    `SELECT user_id FROM members WHERE list_id = ?1 AND user_id IN (SELECT value FROM json_each(?2))
     UNION SELECT user_id FROM assignments WHERE list_id = ?1 AND user_id IN (SELECT value FROM json_each(?2))`,
  )
    .bind(access.list.id, JSON.stringify(others))
    .all<{ user_id: number }>();
  for (const row of rows.results) ok.add(row.user_id);
  return ok;
}

export async function requirePeopleOnList(env: Env, access: Access, targets: number[]): Promise<void> {
  const ok = await onListAlready(env, access, targets);
  if (targets.some((id) => !ok.has(id))) throw new ApiError("bad_request", "Add that person to the list before giving them a task.");
}

export async function peopleStillOnList(env: Env, access: Access, targets: number[]): Promise<number[]> {
  const ok = await onListAlready(env, access, targets);
  return [...new Set(targets)].filter((id) => ok.has(id));
}

interface Fields {
  text?: string;
  priority?: number;
  dueAt?: number | null;
  label?: string | null;
  section?: string | null;
  notes?: string | null;
  assigneeId?: number | null;
  assigneeIds?: number[];
  link?: v.TaskLink | null;
}

function readFields(body: Record<string, unknown>): Fields {
  const f: Fields = {};
  if (body.text !== undefined) f.text = v.text(body.text, "Task", limits.itemMaxLength);
  if (body.priority !== undefined) f.priority = v.priority(body.priority);
  if (body.dueAt !== undefined) f.dueAt = v.timestamp(body.dueAt, "dueAt");
  if (body.label !== undefined) f.label = body.label === null ? null : v.oneOf(body.label, "label", labels);
  if (body.section !== undefined) f.section = v.optionalText(body.section, "Section", limits.sectionMaxLength);
  if (body.notes !== undefined) f.notes = v.optionalText(body.notes, "Notes", limits.notesMaxLength);
  if (body.assigneeIds !== undefined) {
    f.assigneeIds = v.userIds(body.assigneeIds, "assigneeIds", limits.assigneesPerItem);
  } else if (body.assigneeId !== undefined) {
    f.assigneeIds = body.assigneeId === null ? [] : [v.userId(body.assigneeId, "assigneeId")];
  }
  if (f.assigneeIds !== undefined) f.assigneeId = f.assigneeIds[0] ?? null;
  if (body.link !== undefined) f.link = v.link(body.link, limits.linkMaxLength);
  return f;
}

const columnFor: Record<keyof Fields, keyof ItemRow> = {
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

function stored(key: keyof Fields, value: unknown): unknown {
  if (key === "assigneeIds") return Array.isArray(value) && value.length > 0 ? JSON.stringify(value) : null;
  return key === "link" && value !== null && value !== undefined ? JSON.stringify(value) : value;
}

function readStored(key: keyof Fields, value: unknown): unknown {
  if (key === "assigneeIds") return parseIdList((value as string | null) ?? null);
  if (key === "link") return value ? JSON.parse(value as string) : null;
  return value;
}

export async function addItem(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const access = await requireWritable(env, listId, caller.userId, "editor");
  const body = await readBody(request);
  const fields = readFields(body);
  if (fields.text === undefined) throw new ApiError("bad_request", "Task cannot be empty.");
  if (access.list.item_count >= limits.itemsPerList) {
    throw new ApiError("limit_reached", `A list can hold up to ${limits.itemsPerList} tasks.`);
  }
  let assignees = fields.assigneeIds;
  if (assignees === undefined) {
    assignees = await peopleStillOnList(env, access, parseIdList(access.list.auto_assignees));
  } else {
    await requirePeopleOnList(env, access, assignees);
  }

  const top = await env.DB.prepare("SELECT COALESCE(MAX(position), 0) AS top FROM items WHERE list_id = ?")
    .bind(listId)
    .first<{ top: number }>();
  const now = Date.now();
  const id = newId();
  const statements = [
    env.DB.prepare(
      `INSERT INTO items (id, list_id, text, done, position, version, priority, due_at, label, section, notes, assignee_id, assignees, link,
                          created_by, updated_by, created_at, updated_at)
       VALUES (?, ?, ?, 0, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      id,
      listId,
      fields.text,
      (top?.top ?? 0) + 1,
      fields.priority ?? 0,
      fields.dueAt ?? null,
      fields.label ?? null,
      fields.section ?? null,
      fields.notes ?? null,
      assignees[0] ?? null,
      stored("assigneeIds", assignees),
      stored("link", fields.link ?? null),
      caller.userId,
      caller.userId,
      now,
      now,
    ),
    bumpRevision(env, listId),
    ...recordActivity(env, { listId, actorId: caller.userId, kind: "item.added", itemId: id, data: { text: fields.text } }),
  ];
  for (const person of assignees) {
    if (person !== caller.userId) statements.push(notify(env, person, listId, id, caller.userId, "task.assigned", { text: fields.text }));
  }
  await env.DB.batch(statements);
  return json({ item: itemJson(await loadItem(env, id)) }, 201);
}

export async function updateItem(request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const existing = await loadItem(env, itemId);
  const access = await hidden(() => requireWritable(env, existing.list_id, caller.userId, "viewer"));
  const body = await readBody(request);
  const fields = readFields(body);
  const hasDone = body.done !== undefined;
  const done = hasDone ? v.bool(body.done, "done") : existing.done === 1;
  const keys = Object.keys(fields) as (keyof Fields)[];
  if (keys.length === 0 && !hasDone) throw new ApiError("bad_request", "Nothing to change.");

  const isEditor = roleRank[access.role] >= roleRank.editor;
  const isOwnTask = assigneesOf(existing).includes(caller.userId);
  if (!isEditor && !(isOwnTask && keys.length === 0)) throw new ApiError("forbidden", "Only editors can do that.");
  if (fields.assigneeIds) await requirePeopleOnList(env, access, fields.assigneeIds);

  const changes: Record<string, { from: unknown; to: unknown }> = {};
  for (const key of keys) {
    const before = key === "assigneeIds" ? stored(key, assigneesOf(existing)) : existing[columnFor[key]];
    const after = stored(key, fields[key]);
    if (before !== after) changes[key] = { from: readStored(key, before), to: fields[key] };
  }
  const textual = fields.text !== undefined || fields.notes !== undefined;
  const expected = textual && body.version !== undefined ? v.positiveInt(body.version, "version") : null;

  const now = Date.now();
  const sets = keys.map((key, index) => `${columnFor[key]} = ?${index + 6}`);
  const update = env.DB.prepare(
    `UPDATE items SET done = ?1, version = version + 1, updated_by = ?2, updated_at = ?3 ${sets.length ? ", " + sets.join(", ") : ""}
      WHERE id = ?4 AND deleted_at IS NULL AND (?5 IS NULL OR version = ?5)`,
  ).bind(done ? 1 : 0, caller.userId, now, itemId, expected, ...keys.map((key) => stored(key, fields[key])));
  const bump = env.DB.prepare("UPDATE lists SET revision = revision + 1, updated_at = ?1 WHERE id = ?2 AND changes() > 0").bind(
    now,
    existing.list_id,
  );
  const log: D1PreparedStatement[] = [];
  if (Object.keys(changes).length > 0) {
    log.push(
      activityInsert(env, {
        listId: existing.list_id,
        actorId: caller.userId,
        kind: "item.edited",
        itemId,
        data: { text: fields.text ?? existing.text, changes },
        onlyIfChanged: true,
      }),
    );
  }
  if (done !== (existing.done === 1)) {
    log.push(
      activityInsert(env, {
        listId: existing.list_id,
        actorId: caller.userId,
        kind: done ? "item.checked" : "item.unchecked",
        itemId,
        data: { text: fields.text ?? existing.text },
        onlyIfChanged: true,
      }),
    );
  }
  const statements = [update, bump, ...log, activityPrune(env, existing.list_id)];
  if (changes.assigneeIds && fields.assigneeIds) {
    const before = new Set(assigneesOf(existing));
    for (const person of fields.assigneeIds) {
      if (!before.has(person) && person !== caller.userId) {
        statements.push(
          notify(env, person, existing.list_id, itemId, caller.userId, "task.assigned", { text: fields.text ?? existing.text }),
        );
      }
    }
  }
  const [result] = await env.DB.batch(statements);

  if (result.meta.changes === 0) {
    const current = await loadItem(env, itemId);
    return json({ error: { code: "conflict", message: "Someone else changed this task first." }, item: itemJson(current) }, 409);
  }
  return json({ item: itemJson(await loadItem(env, itemId)) });
}

export async function moveItem(request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const existing = await loadItem(env, itemId);
  await hidden(() => requireWritable(env, existing.list_id, caller.userId, "editor"));
  const body = await readBody(request);
  const aboveId = body.aboveId === undefined || body.aboveId === null ? null : v.idText(body.aboveId, "aboveId");
  const belowId = body.belowId === undefined || body.belowId === null ? null : v.idText(body.belowId, "belowId");
  if (aboveId === null && belowId === null) throw new ApiError("bad_request", "Pass aboveId or belowId.");
  if (aboveId === itemId || belowId === itemId) throw new ApiError("bad_request", "A task cannot move next to itself.");
  const section = body.section === undefined ? existing.section : v.optionalText(body.section, "Section", limits.sectionMaxLength);

  const positionOf = async (id: string | null): Promise<number | null> => {
    if (id === null) return null;
    const row = await env.DB.prepare("SELECT position FROM items WHERE id = ? AND list_id = ? AND deleted_at IS NULL")
      .bind(id, existing.list_id)
      .first<{ position: number }>();
    if (!row) throw new ApiError("bad_request", "That neighbour is not a task in this list.");
    return row.position;
  };
  const target = async (): Promise<number> => {
    const above = await positionOf(aboveId);
    const below = await positionOf(belowId);
    if (above !== null && below !== null) return (above + below) / 2;
    return above !== null ? above + 1 : (below as number) - 1;
  };

  let position = await target();
  const above = await positionOf(aboveId);
  const below = await positionOf(belowId);
  if (above !== null && below !== null && (below - above < 1e-6 || below <= above)) {
    await env.DB.prepare(
      `UPDATE items SET position = (SELECT COUNT(*) FROM items j WHERE j.list_id = items.list_id
                                      AND (j.position < items.position OR (j.position = items.position AND j.id < items.id))) + 1
        WHERE list_id = ?`,
    )
      .bind(existing.list_id)
      .run();
    position = await target();
  }

  await env.DB.batch([
    env.DB.prepare("UPDATE items SET position = ?, section = ?, updated_by = ?, updated_at = ? WHERE id = ?").bind(
      position,
      section,
      caller.userId,
      Date.now(),
      itemId,
    ),
    bumpRevision(env, existing.list_id),
    ...recordActivity(env, {
      listId: existing.list_id,
      actorId: caller.userId,
      kind: "item.moved",
      itemId,
      data: { text: existing.text, from: { position: existing.position, section: existing.section }, to: { position, section } },
    }),
  ]);
  return json({ item: itemJson(await loadItem(env, itemId)) });
}

export async function deleteItem(_request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const existing = await loadItem(env, itemId);
  await hidden(() => requireWritable(env, existing.list_id, caller.userId, "editor"));
  await env.DB.batch([
    env.DB.prepare("UPDATE items SET deleted_at = ?, updated_by = ? WHERE id = ? AND deleted_at IS NULL").bind(
      Date.now(),
      caller.userId,
      itemId,
    ),
    bumpRevision(env, existing.list_id),
    ...recordActivity(env, {
      listId: existing.list_id,
      actorId: caller.userId,
      kind: "item.deleted",
      itemId,
      data: { text: existing.text, done: existing.done === 1 },
    }),
  ]);
  return json({ deleted: true, restorableUntil: Date.now() + limits.trashMs });
}

export async function restoreItem(_request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const existing = await loadItem(env, itemId, true);
  const access = await hidden(() => requireWritable(env, existing.list_id, caller.userId, "editor"));
  if (existing.deleted_at === null) return json({ item: itemJson(existing) });
  if (access.list.item_count >= limits.itemsPerList) {
    throw new ApiError("limit_reached", `A list can hold up to ${limits.itemsPerList} tasks.`);
  }
  await env.DB.batch([
    env.DB.prepare("UPDATE items SET deleted_at = NULL, updated_by = ?, updated_at = ? WHERE id = ?").bind(
      caller.userId,
      Date.now(),
      itemId,
    ),
    bumpRevision(env, existing.list_id),
    ...recordActivity(env, { listId: existing.list_id, actorId: caller.userId, kind: "item.restored", itemId, data: { text: existing.text } }),
  ]);
  return json({ item: itemJson(await loadItem(env, itemId)) });
}

export async function myTasks(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT i.*, l.title AS list_title FROM item_assignees ia
       JOIN items i ON i.id = ia.item_id JOIN lists l ON l.id = i.list_id
      WHERE ia.user_id = ? AND i.deleted_at IS NULL AND l.deleted_at IS NULL
      ORDER BY i.done ASC, COALESCE(i.due_at, 9e15) ASC, i.priority DESC, i.updated_at DESC LIMIT ?`,
  )
    .bind(caller.userId, limits.myTasksMaxResults)
    .all<ItemRow & { list_title: string }>();
  return json({ items: rows.results.map((r) => ({ ...itemJson(r), listTitle: r.list_title })) });
}

export async function search(request: Request, env: Env, caller: Caller): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const q = (params.get("q") ?? "").trim().slice(0, 100);
  const label = params.get("label");
  const filterDone = params.get("done");
  const assignee = params.get("assignee");
  if (q.length < 2 && !label && !assignee) throw new ApiError("bad_request", "Type at least 2 characters to search.");
  const like = `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
  const rows = await env.DB.prepare(
    `SELECT i.*, l.title AS list_title FROM items i JOIN lists l ON l.id = i.list_id
      WHERE i.deleted_at IS NULL AND l.deleted_at IS NULL
        AND (l.owner_id = ?1
          OR EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1)
          OR EXISTS (SELECT 1 FROM assignments a WHERE a.list_id = l.id AND a.user_id = ?1)
          OR EXISTS (SELECT 1 FROM visits vi WHERE vi.list_id = l.id AND vi.user_id = ?1)
          OR EXISTS (SELECT 1 FROM item_assignees ia WHERE ia.item_id = i.id AND ia.user_id = ?1))
        AND (?2 = '%%' OR i.text LIKE ?2 ESCAPE '\\' OR i.notes LIKE ?2 ESCAPE '\\')
        AND (?3 IS NULL OR i.label = ?3)
        AND (?4 IS NULL OR i.done = ?4)
        AND (?5 IS NULL OR EXISTS (SELECT 1 FROM item_assignees ib WHERE ib.item_id = i.id AND ib.user_id = ?5))
      ORDER BY i.updated_at DESC LIMIT ?6`,
  )
    .bind(
      caller.userId,
      like,
      label ? v.oneOf(label, "label", labels) : null,
      filterDone === "true" ? 1 : filterDone === "false" ? 0 : null,
      assignee === "me" ? caller.userId : assignee ? v.userId(assignee, "assignee") : null,
      limits.searchMaxResults,
    )
    .all<ItemRow & { list_title: string }>();
  return json({ items: rows.results.map((r) => ({ ...itemJson(r), listTitle: r.list_title })) });
}

export async function requireItemAccess(env: Env, itemId: string, userId: number, minimum: "viewer" | "editor") {
  const item = await loadItem(env, itemId);
  const access = await hidden(() => requireRole(env, item.list_id, userId, minimum));
  return { item, access };
}

export async function splitItem(request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const existing = await loadItem(env, itemId);
  const access = await hidden(() => requireWritable(env, existing.list_id, caller.userId, "editor"));
  const body = await readBody(request);
  if (!Array.isArray(body.parts)) throw new ApiError("bad_request", "parts must be a list of task texts.");
  if (body.parts.length > limits.splitMaxParts) {
    throw new ApiError("bad_request", `A task can be split into up to ${limits.splitMaxParts} tasks at once.`);
  }
  const parts = body.parts.map((part, index) => v.text(part, `Part ${index + 1}`, limits.itemMaxLength));
  if (parts.length < 2) throw new ApiError("bad_request", "Split needs at least two parts.");
  const added = parts.length - 1;
  if (access.list.item_count + added > limits.itemsPerList) {
    throw new ApiError("limit_reached", `A list can hold up to ${limits.itemsPerList} tasks.`);
  }
  const expected = body.version === undefined ? null : v.positiveInt(body.version, "version");
  const listId = existing.list_id;

  const nextPosition = async (from: number): Promise<number | null> => {
    const row = await env.DB.prepare("SELECT MIN(position) AS p FROM items WHERE list_id = ? AND position > ?")
      .bind(listId, from)
      .first<{ p: number | null }>();
    return row?.p ?? null;
  };
  let base = existing.position;
  let next = await nextPosition(base);
  if (next !== null && (next - base) / (added + 1) < 1e-6) {
    await env.DB.prepare(
      `UPDATE items SET position = (SELECT COUNT(*) FROM items j WHERE j.list_id = items.list_id
                                      AND (j.position < items.position OR (j.position = items.position AND j.id < items.id))) + 1
        WHERE list_id = ?`,
    )
      .bind(listId)
      .run();
    base = (await loadItem(env, itemId)).position;
    next = await nextPosition(base);
  }
  const step = next === null ? 1 : (next - base) / (added + 1);

  const now = Date.now();
  const ids = parts.slice(1).map(() => newId());
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `UPDATE items SET text = ?1, version = version + 1, updated_by = ?2, updated_at = ?3
        WHERE id = ?4 AND deleted_at IS NULL AND (?5 IS NULL OR version = ?5)`,
    ).bind(parts[0], caller.userId, now, itemId, expected),
  ];
  ids.forEach((id, index) => {
    statements.push(
      env.DB.prepare(
        `INSERT INTO items (id, list_id, text, done, position, version, priority, due_at, label, section, notes, assignee_id, assignees, link,
                            created_by, updated_by, created_at, updated_at)
         SELECT ?1, ?2, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, NULL, ?10, ?11, NULL, ?12, ?12, ?13, ?13 WHERE changes() > 0`,
      ).bind(
        id,
        listId,
        parts[index + 1],
        existing.done,
        base + step * (index + 1),
        existing.priority,
        existing.due_at,
        existing.label,
        existing.section,
        existing.assignee_id,
        existing.assignees,
        caller.userId,
        now,
      ),
    );
  });
  statements.push(
    bumpRevisionIfChanged(env, listId),
    ...ids.map((id, index) =>
      activityInsert(env, {
        listId,
        actorId: caller.userId,
        kind: "item.added",
        itemId: id,
        data: { text: parts[index + 1] },
        onlyIfChanged: true,
      }),
    ),
    activityInsert(env, {
      listId,
      actorId: caller.userId,
      kind: "item.split",
      itemId,
      data: { text: existing.text, from: existing.text, to: parts[0], added: ids },
      onlyIfChanged: true,
    }),
    activityPrune(env, listId),
  );
  const [result] = await env.DB.batch(statements);
  if (result.meta.changes === 0) {
    const current = await loadItem(env, itemId);
    return json({ error: { code: "conflict", message: "Someone else changed this task first." }, item: itemJson(current) }, 409);
  }
  return getListPayload(env, listId, caller.userId);
}
