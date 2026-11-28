import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { requireRole, roleRank, type ListRow, type Role } from "../access";
import { hashKey, newId, newShareCode, randomToken } from "../crypto";
import { labels, limits, templates } from "../config";
import * as v from "../validate";
import { recordActivity } from "../activity";
import { itemJson, type ItemRow } from "./items";
import { usersById } from "../users";

interface SummaryRow extends ListRow {
  role: Role;
  seen_revision: number | null;
  unseen: number;
}

function summary(row: SummaryRow) {
  return {
    id: row.id,
    title: row.title,
    ownerId: row.owner_id,
    role: row.role,
    itemCount: row.item_count,
    doneCount: row.done_count,
    revision: row.revision,
    seenRevision: row.seen_revision,
    unseen: row.unseen,
    archived: row.archived_at !== null,
    placeId: row.place_id,
    updatedAt: row.updated_at,
    shareCode: roleRank[row.role] >= roleRank.editor ? row.share_code : null,
  };
}

const summaryColumns = `
  l.*,
  CASE WHEN l.owner_id = ?1 THEN 'owner'
       ELSE COALESCE((SELECT role FROM members m WHERE m.list_id = l.id AND m.user_id = ?1), 'viewer') END AS role,
  (SELECT s.revision FROM seen s WHERE s.list_id = l.id AND s.user_id = ?1) AS seen_revision,
  (SELECT COUNT(*) FROM activity a WHERE a.list_id = l.id AND a.actor_id <> ?1
      AND a.revision > COALESCE((SELECT s.revision FROM seen s WHERE s.list_id = l.id AND s.user_id = ?1), l.revision)) AS unseen`;

export async function home(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const [mine, assigned, opened] = await env.DB.batch<SummaryRow>([
    env.DB.prepare(
      `SELECT ${summaryColumns} FROM lists l
        WHERE l.deleted_at IS NULL
          AND (l.owner_id = ?1 OR EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1))
        ORDER BY l.updated_at DESC`,
    ).bind(caller.userId),
    env.DB.prepare(
      `SELECT ${summaryColumns} FROM lists l
        WHERE l.deleted_at IS NULL AND l.owner_id <> ?1
          AND NOT EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1)
          AND (EXISTS (SELECT 1 FROM assignments a WHERE a.list_id = l.id AND a.user_id = ?1)
            OR EXISTS (SELECT 1 FROM items i WHERE i.list_id = l.id AND i.assignee_id = ?1 AND i.deleted_at IS NULL))
        ORDER BY l.updated_at DESC`,
    ).bind(caller.userId),
    env.DB.prepare(
      `SELECT ${summaryColumns} FROM lists l
         JOIN visits vi ON vi.list_id = l.id AND vi.user_id = ?1
        WHERE l.deleted_at IS NULL AND l.owner_id <> ?1
          AND NOT EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1)
          AND NOT EXISTS (SELECT 1 FROM assignments a WHERE a.list_id = l.id AND a.user_id = ?1)
        ORDER BY vi.opened_at DESC`,
    ).bind(caller.userId),
  ]);
  return json({
    mine: mine.results.map(summary),
    assigned: assigned.results.map(summary),
    opened: opened.results.map(summary),
  });
}

async function requireListRoom(env: Env, userId: number): Promise<void> {
  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM lists WHERE owner_id = ? AND deleted_at IS NULL")
    .bind(userId)
    .first<{ n: number }>();
  if ((count?.n ?? 0) >= limits.listsPerOwner) {
    throw new ApiError("limit_reached", `You can own up to ${limits.listsPerOwner} lists. Delete or empty the trash to make room.`);
  }
}

interface SeedItem {
  text: string;
  done?: boolean;
  priority?: number;
  label?: string | null;
  section?: string | null;
  notes?: string | null;
  dueAt?: number | null;
}

async function insertList(env: Env, caller: Caller, title: string, seed: SeedItem[], kind: "list.created" | "list.imported") {
  const now = Date.now();
  const id = newId();
  for (let attempt = 0; attempt < 3; attempt++) {
    const [result] = await env.DB.batch([
      env.DB.prepare(
        `INSERT OR IGNORE INTO lists (id, owner_id, title, share_code, revision, created_at, updated_at)
         VALUES (?, ?, ?, ?, 1, ?, ?)`,
      ).bind(id, caller.userId, title, newShareCode(), now, now),
      ...recordActivity(env, { listId: id, actorId: caller.userId, kind, data: { title, items: seed.length }, onlyIfChanged: true }),
    ]);
    if (result.meta.changes === 1) break;
    if (attempt === 2) throw new ApiError("internal", "Could not create the list. Try again.");
  }
  for (let start = 0; start < seed.length; start += 50) {
    await env.DB.batch(
      seed.slice(start, start + 50).map((s, offset) =>
        env.DB.prepare(
          `INSERT INTO items (id, list_id, text, done, position, version, priority, due_at, label, section, notes,
                              created_by, updated_by, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          newId(),
          id,
          s.text,
          s.done ? 1 : 0,
          start + offset + 1,
          s.priority ?? 0,
          s.dueAt ?? null,
          s.label ?? null,
          s.section ?? null,
          s.notes ?? null,
          caller.userId,
          caller.userId,
          now,
          now,
        ),
      ),
    );
  }
  return id;
}

export async function createList(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  let seed: SeedItem[] = [];
  let title: string;
  if (body.template !== undefined) {
    const template = templates[v.oneOf(body.template, "template", Object.keys(templates))];
    title = body.title === undefined ? template.title : v.text(body.title, "Title", limits.titleMaxLength);
    seed = template.sections.flatMap((section) => section.items.map((text) => ({ text, section: section.name })));
  } else {
    title = v.text(body.title, "Title", limits.titleMaxLength);
  }
  await requireListRoom(env, caller.userId);
  const id = await insertList(env, caller, title, seed, "list.created");
  return getListPayload(env, id, caller.userId, 201);
}

export async function listTemplates(): Promise<Response> {
  return json({
    templates: Object.entries(templates).map(([key, t]) => ({
      key,
      title: t.title,
      itemCount: t.sections.reduce((n, s) => n + s.items.length, 0),
    })),
  });
}

export async function duplicateList(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const { list } = await requireRole(env, listId, caller.userId, "viewer");
  const body = await readBody(request);
  const title = body.title === undefined ? `${list.title} copy`.slice(0, limits.titleMaxLength) : v.text(body.title, "Title", limits.titleMaxLength);
  await requireListRoom(env, caller.userId);
  const rows = await env.DB.prepare("SELECT * FROM items WHERE list_id = ? AND deleted_at IS NULL ORDER BY position ASC")
    .bind(listId)
    .all<ItemRow>();
  const seed = rows.results.map((r) => ({
    text: r.text,
    done: body.keepDone === true && r.done === 1,
    priority: r.priority,
    label: r.label,
    section: r.section,
    notes: r.notes,
    dueAt: r.due_at,
  }));
  const id = await insertList(env, caller, title, seed, "list.created");
  return getListPayload(env, id, caller.userId, 201);
}

export async function openByCode(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  const code = v.shareCode(body.code);
  const list = await env.DB.prepare("SELECT id, owner_id FROM lists WHERE share_code = ? AND deleted_at IS NULL")
    .bind(code)
    .first<{ id: string; owner_id: number }>();
  if (!list) throw new ApiError("not_found", "No list uses that code. Check it with the owner.");
  if (list.owner_id !== caller.userId) {
    await env.DB.prepare(
      `INSERT INTO visits (list_id, user_id, opened_at) VALUES (?, ?, ?)
       ON CONFLICT (list_id, user_id) DO UPDATE SET opened_at = excluded.opened_at`,
    )
      .bind(list.id, caller.userId, Date.now())
      .run();
  }
  return getListPayload(env, list.id, caller.userId);
}

export async function getList(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const rev = new URL(request.url).searchParams.get("rev");
  if (rev !== null) {
    const access = await requireRole(env, listId, caller.userId, "viewer");
    if (String(access.list.revision) === rev) {
      return json({ changed: false, revision: access.list.revision, role: access.role });
    }
  }
  return getListPayload(env, listId, caller.userId);
}

const itemEventKinds = new Set([
  "item.added",
  "item.edited",
  "item.checked",
  "item.unchecked",
  "item.deleted",
  "item.restored",
  "item.moved",
  "comment.added",
]);

export async function listChanges(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const access = await requireRole(env, listId, caller.userId, "viewer");
  const sinceParam = new URL(request.url).searchParams.get("since") ?? "";
  if (!/^\d{1,15}$/.test(sinceParam)) throw new ApiError("bad_request", "since must be a revision number.");
  const since = Number(sinceParam);
  const current = access.list.revision;
  if (since === current) return json({ mode: "none", revision: current, role: access.role });

  const events = await env.DB.prepare(
    "SELECT revision, kind, item_id, actor_id FROM activity WHERE list_id = ? AND revision > ? ORDER BY id ASC",
  )
    .bind(listId, since)
    .all<{ revision: number; kind: string; item_id: string | null; actor_id: number }>();
  const othersChanged = events.results.some((e) => e.actor_id !== caller.userId);
  const full = async () => {
    const payload = (await (await getListPayload(env, listId, caller.userId)).json()) as Record<string, unknown>;
    return json({ ...payload, othersChanged });
  };
  if (since > current || current - since > limits.activityPerList) return full();

  const revisions = new Set(events.results.map((e) => e.revision));
  const covered = revisions.size === current - since && events.results.every((e) => itemEventKinds.has(e.kind) && e.item_id);
  if (!covered) return full();

  const ids = [...new Set(events.results.map((e) => e.item_id as string))];
  const rows = await env.DB.prepare(
    `SELECT i.*, (SELECT COUNT(*) FROM comments c WHERE c.item_id = i.id) AS comment_count
       FROM items i WHERE i.list_id = ? AND i.id IN (${ids.map(() => "?").join(",")})`,
  )
    .bind(listId, ...ids)
    .all<ItemRow & { comment_count: number }>();
  const live = rows.results.filter((r) => r.deleted_at === null);
  const liveIds = new Set(live.map((r) => r.id));
  return json({
    mode: "delta",
    revision: current,
    role: access.role,
    items: live.map((r) => ({ ...itemJson(r), commentCount: r.comment_count })),
    removed: ids.filter((id) => !liveIds.has(id)),
    othersChanged,
  });
}

export async function getListPayload(env: Env, listId: string, userId: number, status = 200): Promise<Response> {
  const access = await requireRole(env, listId, userId, "viewer");
  const { list, role } = access;
  const canSeePeople = roleRank[role] >= roleRank.editor;

  const statements = [
    env.DB.prepare(
      `SELECT i.*, (SELECT COUNT(*) FROM comments c WHERE c.item_id = i.id) AS comment_count
         FROM items i WHERE i.list_id = ? AND i.deleted_at IS NULL ORDER BY i.position ASC`,
    ).bind(listId),
    env.DB.prepare(
      "SELECT user_id, item_id, place_id, updated_at FROM presence WHERE list_id = ? AND user_id <> ? AND updated_at > ?",
    ).bind(listId, userId, Date.now() - limits.presenceTtlMs),
    env.DB.prepare("SELECT user_id, role FROM members WHERE list_id = ? ORDER BY added_at ASC").bind(listId),
    env.DB.prepare("SELECT user_id FROM assignments WHERE list_id = ? ORDER BY assigned_at ASC").bind(listId),
  ];
  const [items, presence, members, assignments] = await env.DB.batch<Record<string, unknown>>(statements);

  const peopleIds = [
    list.owner_id,
    ...members.results.map((r) => r.user_id as number),
    ...assignments.results.map((r) => r.user_id as number),
    ...items.results.map((r) => r.assignee_id as number | null).filter((id): id is number => id !== null),
    ...presence.results.map((r) => r.user_id as number),
  ];
  const names = await usersById(env, peopleIds);
  const person = (id: number) => {
    const u = names.get(id);
    return { userId: id, name: u?.name ?? null, displayName: u?.displayName ?? null };
  };

  return json(
    {
      changed: true,
      revision: list.revision,
      role,
      assigned: access.assigned,
      list: {
        id: list.id,
        title: list.title,
        ownerId: list.owner_id,
        owner: person(list.owner_id),
        shareCode: canSeePeople ? list.share_code : null,
        archived: list.archived_at !== null,
        placeId: list.place_id,
        itemCount: list.item_count,
        doneCount: list.done_count,
        updatedAt: list.updated_at,
      },
      items: items.results.map((r) => ({ ...itemJson(r as unknown as ItemRow), commentCount: r.comment_count as number })),
      members: canSeePeople ? members.results.map((r) => ({ ...person(r.user_id as number), role: r.role })) : [],
      assignments: canSeePeople ? assignments.results.map((r) => person(r.user_id as number)) : [],
      people: [...names.values()],
      presence: presence.results.map((r) => ({
        ...person(r.user_id as number),
        itemId: r.item_id,
        placeId: r.place_id,
        updatedAt: r.updated_at,
      })),
    },
    status,
  );
}

export async function updateList(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const access = await requireRole(env, listId, caller.userId, "admin");
  const { list } = access;
  const body = await readBody(request);
  const statements: D1PreparedStatement[] = [];
  const now = Date.now();

  if (body.archived !== undefined) {
    if (access.role !== "owner") throw new ApiError("forbidden", "Only the owner can do that.");
    const archived = v.bool(body.archived, "archived");
    if (archived !== (list.archived_at !== null)) {
      statements.push(
        env.DB.prepare("UPDATE lists SET archived_at = ?, revision = revision + 1, updated_at = ? WHERE id = ?").bind(
          archived ? now : null,
          now,
          listId,
        ),
        ...recordActivity(env, { listId, actorId: caller.userId, kind: archived ? "list.archived" : "list.unarchived" }),
      );
    }
  }
  if (body.title !== undefined) {
    if (list.archived_at !== null && body.archived !== false) {
      throw new ApiError("forbidden", "This list is archived. Unarchive it to make changes.");
    }
    const title = v.text(body.title, "Title", limits.titleMaxLength);
    if (title !== list.title) {
      statements.push(
        env.DB.prepare("UPDATE lists SET title = ?, revision = revision + 1, updated_at = ? WHERE id = ?").bind(title, now, listId),
        ...recordActivity(env, { listId, actorId: caller.userId, kind: "list.renamed", data: { from: list.title, to: title } }),
      );
    }
  }
  if (body.placeId !== undefined) {
    const placeId = body.placeId === null ? null : v.userId(body.placeId, "placeId");
    if (placeId !== list.place_id) {
      statements.push(
        env.DB.prepare("UPDATE lists SET place_id = ?, revision = revision + 1, updated_at = ? WHERE id = ?").bind(placeId, now, listId),
        ...recordActivity(env, { listId, actorId: caller.userId, kind: "list.pinned", data: { from: list.place_id, to: placeId } }),
      );
    }
  }
  if (statements.length === 0 && body.title === undefined && body.archived === undefined && body.placeId === undefined) {
    throw new ApiError("bad_request", "Nothing to change.");
  }
  if (statements.length > 0) await env.DB.batch(statements);
  return getListPayload(env, listId, caller.userId);
}

export async function deleteList(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "owner");
  await env.DB.prepare("UPDATE lists SET deleted_at = ?, revision = revision + 1 WHERE id = ?").bind(Date.now(), listId).run();
  return json({ deleted: true, restorableUntil: Date.now() + limits.trashMs });
}

export async function restoreList(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT owner_id, deleted_at FROM lists WHERE id = ?")
    .bind(listId)
    .first<{ owner_id: number; deleted_at: number | null }>();
  if (!row || row.owner_id !== caller.userId) throw new ApiError("not_found", "This list does not exist or you no longer have access.");
  if (row.deleted_at !== null) {
    await requireListRoom(env, caller.userId);
    await env.DB.prepare("UPDATE lists SET deleted_at = NULL, revision = revision + 1, updated_at = ? WHERE id = ?")
      .bind(Date.now(), listId)
      .run();
  }
  return getListPayload(env, listId, caller.userId);
}

export async function trash(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const since = Date.now() - limits.trashMs;
  const [lists, items, notes] = await env.DB.batch<Record<string, unknown>>([
    env.DB.prepare(
      "SELECT id, title, item_count, deleted_at FROM lists WHERE owner_id = ? AND deleted_at IS NOT NULL AND deleted_at > ? ORDER BY deleted_at DESC",
    ).bind(caller.userId, since),
    env.DB.prepare(
      `SELECT i.id, i.text, i.list_id, i.deleted_at, l.title AS list_title FROM items i JOIN lists l ON l.id = i.list_id
        WHERE i.deleted_at IS NOT NULL AND i.deleted_at > ?2 AND l.deleted_at IS NULL
          AND (l.owner_id = ?1 OR EXISTS (SELECT 1 FROM members m WHERE m.list_id = l.id AND m.user_id = ?1 AND m.role IN ('admin', 'editor')))
        ORDER BY i.deleted_at DESC LIMIT 200`,
    ).bind(caller.userId, since),
    env.DB.prepare(
      `SELECT n.id, n.kind, n.data, n.actor_id, n.created_at, n.deleted_at, l.title AS list_title
         FROM notifications n JOIN lists l ON l.id = n.list_id
        WHERE n.user_id = ? AND n.deleted_at IS NOT NULL AND n.created_at > ?
        ORDER BY n.deleted_at DESC LIMIT 100`,
    ).bind(caller.userId, Date.now() - limits.notificationMaxAgeMs),
  ]);
  return json({
    lists: lists.results.map((r) => ({
      id: r.id,
      title: r.title,
      itemCount: r.item_count,
      deletedAt: r.deleted_at,
      restorableUntil: (r.deleted_at as number) + limits.trashMs,
    })),
    items: items.results.map((r) => ({
      id: r.id,
      text: r.text,
      listId: r.list_id,
      listTitle: r.list_title,
      deletedAt: r.deleted_at,
      restorableUntil: (r.deleted_at as number) + limits.trashMs,
    })),
    notifications: notes.results.map((r) => ({
      id: r.id,
      kind: r.kind,
      data: r.data ? JSON.parse(r.data as string) : null,
      actorId: r.actor_id,
      listTitle: r.list_title,
      createdAt: r.created_at,
      deletedAt: r.deleted_at,
      read: true,
      restorableUntil: (r.created_at as number) + limits.notificationMaxAgeMs,
    })),
  });
}

export async function rotateCode(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "admin");
  for (let attempt = 0; attempt < 3; attempt++) {
    const results = await env.DB.batch([
      env.DB.prepare(
        "UPDATE OR IGNORE lists SET share_code = ?, revision = revision + 1, updated_at = ? WHERE id = ?",
      ).bind(newShareCode(), Date.now(), listId),
      ...recordActivity(env, { listId, actorId: caller.userId, kind: "code.rotated", onlyIfChanged: true }),
      env.DB.prepare("DELETE FROM visits WHERE list_id = ?").bind(listId),
    ]);
    if (results[0].meta.changes === 1) return getListPayload(env, listId, caller.userId);
  }
  throw new ApiError("internal", "Could not make a new code. Try again.");
}

export async function forgetVisit(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await env.DB.prepare("DELETE FROM visits WHERE list_id = ? AND user_id = ?").bind(listId, caller.userId).run();
  return json({ removed: true });
}

export async function markSeen(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  const { list } = await requireRole(env, listId, caller.userId, "viewer");
  const body = await readBody(request);
  const revision = body.revision === undefined ? list.revision : Math.min(v.positiveInt(body.revision, "revision"), list.revision);
  await env.DB.prepare(
    `INSERT INTO seen (list_id, user_id, revision, seen_at) VALUES (?, ?, ?, ?)
     ON CONFLICT (list_id, user_id) DO UPDATE SET revision = MAX(seen.revision, excluded.revision), seen_at = excluded.seen_at`,
  )
    .bind(listId, caller.userId, revision, Date.now())
    .run();
  return json({ seenRevision: revision });
}

export async function putPresence(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "viewer");
  const body = await readBody(request);
  const itemId = body.itemId === undefined || body.itemId === null ? null : v.idText(body.itemId, "itemId");
  const placeId = body.placeId === undefined || body.placeId === null ? null : v.userId(body.placeId, "placeId");
  await env.DB.prepare(
    `INSERT INTO presence (list_id, user_id, item_id, place_id, updated_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (list_id, user_id) DO UPDATE SET item_id = excluded.item_id, place_id = excluded.place_id, updated_at = excluded.updated_at`,
  )
    .bind(listId, caller.userId, itemId, placeId, Date.now())
    .run();
  return json({ ok: true });
}

export async function deletePresence(_request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await env.DB.prepare("DELETE FROM presence WHERE list_id = ? AND user_id = ?").bind(listId, caller.userId).run();
  return json({ ok: true });
}

export async function createExport(request: Request, env: Env, caller: Caller, listId: string): Promise<Response> {
  await requireRole(env, listId, caller.userId, "viewer");
  const body = await readBody(request);
  const format = v.oneOf(body.format ?? "json", "format", ["json", "md"] as const);
  const tz = parseTz(body.tz);
  const token = randomToken();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM export_tokens WHERE expires_at < ?").bind(Date.now()),
    env.DB.prepare("INSERT INTO export_tokens (token_hash, list_id, user_id, format, expires_at, tz) VALUES (?, ?, ?, ?, ?, ?)").bind(
      await hashKey(token),
      listId,
      caller.userId,
      format,
      Date.now() + limits.exportTtlMs,
      tz ? JSON.stringify(tz) : null,
    ),
  ]);
  return json({ url: `${env.publicOrigin}/export/${token}`, expiresAt: Date.now() + limits.exportTtlMs });
}

type TzRange = [number, number];

function parseTz(raw: unknown): TzRange[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 50) return null;
  const out: TzRange[] = [];
  for (const entry of raw) {
    if (!Array.isArray(entry) || entry.length !== 2) return null;
    const [from, offset] = entry;
    if (!Number.isSafeInteger(from) || !Number.isInteger(offset) || offset < -840 || offset > 840) return null;
    out.push([from, offset]);
  }
  return out.sort((a, b) => a[0] - b[0]);
}

function offsetAt(tz: TzRange[] | null, ms: number): number | null {
  if (!tz) return null;
  let pick = tz[0][1];
  for (const [from, offset] of tz) {
    if (from > ms) break;
    pick = offset;
  }
  return pick;
}

function dueText(ms: number, tz: TzRange[] | null): string {
  const offset = offsetAt(tz, ms);
  const local = new Date(ms + (offset ?? 0) * 60_000).toISOString();
  const stamp = `${local.slice(0, 10)} ${local.slice(11, 16)}`;
  if (!offset) return `${stamp} UTC`;
  const abs = Math.abs(offset);
  const hours = String(Math.floor(abs / 60)).padStart(2, "0");
  const minutes = String(abs % 60).padStart(2, "0");
  return `${stamp} UTC${offset < 0 ? "-" : "+"}${hours}:${minutes}`;
}

const dueToken = /\sdue (\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?(?: UTC(?:([+-])(\d{2}):(\d{2}))?)?(?=\s|$)/;

function readDue(text: string): { text: string; dueAt: number | null } {
  const match = dueToken.exec(text);
  if (!match) return { text, dueAt: null };
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const hour = match[4] === undefined ? 23 : Number(match[4]);
  const minute = match[5] === undefined ? 59 : Number(match[5]);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return { text, dueAt: null };
  const offset = match[6] ? (match[6] === "-" ? -1 : 1) * (Number(match[7]) * 60 + Number(match[8])) : 0;
  const dueAt = Date.UTC(year, month - 1, day, hour, minute) - offset * 60_000;
  return { text: text.replace(match[0], ""), dueAt };
}

function toMarkdown(title: string, items: ItemRow[], tz: TzRange[] | null): string {
  const lines = [`# ${title}`, ""];
  let section: string | null | undefined;
  for (const item of items) {
    if (item.section !== section) {
      section = item.section;
      if (section) lines.push("", `## ${section}`, "");
    }
    const extras = [
      item.label ? `[${item.label}]` : "",
      item.priority ? `!${item.priority}` : "",
      item.due_at ? `due ${dueText(item.due_at, tz)}` : "",
    ].filter(Boolean);
    lines.push(`- [${item.done ? "x" : " "}] ${item.text}${extras.length ? " " + extras.join(" ") : ""}`);
    if (item.notes) for (const note of item.notes.split("\n")) lines.push(`  > ${note}`);
  }
  return lines.join("\n") + "\n";
}

export async function downloadExport(_request: Request, env: Env, token: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT * FROM export_tokens WHERE token_hash = ? AND expires_at > ?")
    .bind(await hashKey(token), Date.now())
    .first<{ list_id: string; user_id: number; format: "json" | "md"; tz: string | null }>();
  if (!row) return new Response("This export link expired. Make a new one from the plugin.", { status: 410 });
  let tz: TzRange[] | null = null;
  try {
    tz = row.tz ? parseTz(JSON.parse(row.tz)) : null;
  } catch {
    tz = null;
  }
  const access = await requireRole(env, row.list_id, row.user_id, "viewer");
  const items = await env.DB.prepare("SELECT * FROM items WHERE list_id = ? AND deleted_at IS NULL ORDER BY position ASC")
    .bind(row.list_id)
    .all<ItemRow>();
  const safeName = access.list.title.replace(/[^A-Za-z0-9 ]+/g, "").trim().replace(/ +/g, " ") || "list";
  const body =
    row.format === "md"
      ? toMarkdown(access.list.title, items.results, tz)
      : JSON.stringify(
          {
            format: "checkpointltc.list",
            version: 1,
            title: access.list.title,
            exportedAt: new Date().toISOString(),
            items: items.results.map((r) => ({
              text: r.text,
              done: r.done === 1,
              priority: r.priority,
              label: r.label,
              section: r.section,
              notes: r.notes,
              dueAt: r.due_at,
              due: r.due_at ? dueText(r.due_at, tz) : null,
            })),
          },
          null,
          2,
        );
  return new Response(body, {
    headers: {
      "content-type": row.format === "md" ? "text/markdown; charset=utf-8" : "application/json; charset=utf-8",
      "content-disposition": `attachment; filename="${safeName}.${row.format}"`,
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function parseMarkdown(content: string): { title: string | null; items: SeedItem[] } {
  let title: string | null = null;
  let section: string | null = null;
  const items: SeedItem[] = [];
  for (const raw of content.split(/\r?\n/)) {
    const line = raw.trimEnd();
    const heading = /^(#{1,3})\s+(.+)$/.exec(line);
    if (heading) {
      if (heading[1] === "#" && title === null) title = heading[2].trim();
      else section = heading[2].trim();
      continue;
    }
    const task = /^\s*[-*]\s+(?:\[( |x|X)\]\s+)?(.+)$/.exec(line);
    if (task) {
      const due = readDue(" " + task[2].trim());
      let text = due.text.trim();
      let label: string | null = null;
      let priority = 0;
      const labelMatch = /\s\[(Scripting|UI|VFX|Bug)\]/.exec(text);
      if (labelMatch) {
        label = labelMatch[1];
        text = text.replace(labelMatch[0], "");
      }
      const priorityMatch = /\s!([0-3])\b/.exec(text);
      if (priorityMatch) {
        priority = Number(priorityMatch[1]);
        text = text.replace(priorityMatch[0], "");
      }
      items.push({ text: text.trim(), done: task[1] === "x" || task[1] === "X", label, priority, section, dueAt: due.dueAt });
      continue;
    }
    const note = /^\s+>\s?(.*)$/.exec(line);
    if (note && items.length > 0) {
      const last = items[items.length - 1];
      last.notes = last.notes ? `${last.notes}\n${note[1]}` : note[1];
    }
  }
  return { title, items };
}

export async function importList(request: Request, env: Env, caller: Caller): Promise<Response> {
  const raw = await request.text();
  if (raw.length > limits.importMaxBytes) throw new ApiError("bad_request", "That file is too big to import.");
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new ApiError("bad_request", "Request body is not valid JSON.");
  }
  const format = v.oneOf(body.format, "format", ["json", "md"] as const);
  if (typeof body.content !== "string" || body.content.length === 0) throw new ApiError("bad_request", "content is empty.");

  let parsedTitle: string | null = null;
  let rawItems: SeedItem[];
  if (format === "md") {
    const parsed = parseMarkdown(body.content);
    parsedTitle = parsed.title;
    rawItems = parsed.items;
  } else {
    let data: { title?: unknown; items?: unknown };
    try {
      data = JSON.parse(body.content);
    } catch {
      throw new ApiError("bad_request", "That file is not valid JSON.");
    }
    if (!Array.isArray(data.items)) throw new ApiError("bad_request", "That JSON has no items list.");
    parsedTitle = typeof data.title === "string" ? data.title : null;
    rawItems = data.items as SeedItem[];
  }
  if (rawItems.length > limits.importMaxItems) {
    throw new ApiError("limit_reached", `A list can hold up to ${limits.itemsPerList} tasks.`);
  }
  const seed: SeedItem[] = rawItems.map((item, index) => {
    const where = `Task ${index + 1}`;
    if (typeof item !== "object" || item === null) throw new ApiError("bad_request", `${where} is not valid.`);
    return {
      text: v.text(item.text, where, limits.itemMaxLength),
      done: item.done === true,
      priority: item.priority === undefined ? 0 : v.priority(item.priority),
      label: item.label === undefined || item.label === null ? null : v.oneOf(item.label, `${where} label`, labels),
      section: item.section === undefined ? null : v.optionalText(item.section, `${where} section`, limits.sectionMaxLength),
      notes: item.notes === undefined ? null : v.optionalText(item.notes, `${where} notes`, limits.notesMaxLength),
      dueAt: item.dueAt === undefined ? null : v.timestamp(item.dueAt, `${where} dueAt`),
    };
  });
  const title = v.text(body.title ?? parsedTitle ?? "Imported list", "Title", limits.titleMaxLength);
  await requireListRoom(env, caller.userId);
  const id = await insertList(env, caller, title, seed, "list.imported");
  return getListPayload(env, id, caller.userId, 201);
}

