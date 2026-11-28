import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { newId } from "../crypto";
import { limits } from "../config";
import * as v from "../validate";
import { assigneesOf, requireItemAccess } from "./items";
import { recordActivity } from "../activity";
import { notify } from "../notifications";
import { bumpRevision } from "../access";

interface CommentRow {
  id: string;
  item_id: string;
  author_id: number;
  body: string;
  mentions: string | null;
  created_at: number;
}

const commentJson = (r: CommentRow) => ({
  id: r.id,
  itemId: r.item_id,
  authorId: r.author_id,
  body: r.body,
  mentions: r.mentions ? (JSON.parse(r.mentions) as number[]) : [],
  createdAt: r.created_at,
});

export async function listComments(_request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  await requireItemAccess(env, itemId, caller.userId, "viewer");
  const rows = await env.DB.prepare("SELECT * FROM comments WHERE item_id = ? ORDER BY created_at ASC LIMIT ?")
    .bind(itemId, limits.commentsPerItem)
    .all<CommentRow>();
  return json({ comments: rows.results.map(commentJson) });
}

async function peopleOnList(env: Env, listId: string, ownerId: number): Promise<{ userId: number; name: string | null }[]> {
  const rows = await env.DB.prepare(
    `SELECT p.user_id, r.name FROM (
        SELECT ?2 AS user_id
        UNION SELECT user_id FROM members WHERE list_id = ?1
        UNION SELECT user_id FROM assignments WHERE list_id = ?1
     ) p LEFT JOIN roblox_users r ON r.user_id = p.user_id`,
  )
    .bind(listId, ownerId)
    .all<{ user_id: number; name: string | null }>();
  return rows.results.map((r) => ({ userId: r.user_id, name: r.name }));
}

export async function addComment(request: Request, env: Env, caller: Caller, itemId: string): Promise<Response> {
  const { item, access } = await requireItemAccess(env, itemId, caller.userId, "viewer");
  if (access.role === "viewer" && !assigneesOf(item).includes(caller.userId)) {
    throw new ApiError("forbidden", "Only editors and the person the task is assigned to can comment.");
  }
  if (access.list.archived_at !== null) throw new ApiError("forbidden", "This list is archived. Unarchive it to make changes.");
  const body = await readBody(request);
  const text = v.optionalText(body.body, "Comment", limits.commentMaxLength);
  if (!text) throw new ApiError("bad_request", "Comment cannot be empty.");

  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM comments WHERE item_id = ?").bind(itemId).first<{ n: number }>();
  if ((count?.n ?? 0) >= limits.commentsPerItem) {
    throw new ApiError("limit_reached", `A task can hold up to ${limits.commentsPerItem} comments.`);
  }

  const people = await peopleOnList(env, item.list_id, access.list.owner_id);
  const named = new Set([...text.matchAll(/@([A-Za-z0-9_]{3,20})/g)].map((m) => m[1].toLowerCase()));
  const mentions = people.filter((p) => p.name && named.has(p.name.toLowerCase()) && p.userId !== caller.userId).map((p) => p.userId);

  const id = newId();
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO comments (id, item_id, list_id, author_id, body, mentions, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ).bind(id, itemId, item.list_id, caller.userId, text, mentions.length ? JSON.stringify(mentions) : null, now),
    bumpRevision(env, item.list_id),
    ...recordActivity(env, {
      listId: item.list_id,
      actorId: caller.userId,
      kind: "comment.added",
      itemId,
      data: { text: item.text, comment: text.slice(0, 120) },
    }),
    ...mentions.map((userId) =>
      notify(env, userId, item.list_id, itemId, caller.userId, "comment.mention", { text: item.text, comment: text.slice(0, 120) }),
    ),
  ]);
  const row = await env.DB.prepare("SELECT * FROM comments WHERE id = ?").bind(id).first<CommentRow>();
  return json({ comment: commentJson(row as CommentRow) }, 201);
}

export async function deleteComment(_request: Request, env: Env, caller: Caller, commentId: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT * FROM comments WHERE id = ?").bind(commentId).first<CommentRow & { list_id: string }>();
  if (!row) throw new ApiError("not_found", "That comment was already deleted.");
  const { access } = await requireItemAccess(env, row.item_id, caller.userId, "viewer");
  const canModerate = access.role === "owner" || access.role === "admin";
  if (row.author_id !== caller.userId && !canModerate) throw new ApiError("forbidden", "Only the author, an admin or the owner can delete it.");
  await env.DB.batch([
    env.DB.prepare("DELETE FROM comments WHERE id = ?").bind(commentId),
    bumpRevision(env, row.list_id),
  ]);
  return json({ deleted: true });
}
