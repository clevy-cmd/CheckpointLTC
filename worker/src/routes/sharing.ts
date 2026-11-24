import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { bumpRevision, bumpRevisionIfChanged, requireRole, type Access, type MemberRole } from "../access";
import { userExists } from "../users";
import { limits } from "../config";
import * as v from "../validate";
import { recordActivity } from "../activity";
import { notify } from "../notifications";

type Table = "members" | "assignments";

async function requireRealOtherUser(env: Env, caller: Caller, target: number, ownerId: number): Promise<void> {
  if (target === ownerId || target === caller.userId) {
    throw new ApiError("bad_request", "The owner already has full access.");
  }
  if (!(await userExists(env, target))) throw new ApiError("bad_request", "No Roblox account has that UserId.");
}

async function requireRoom(env: Env, table: Table, listId: string, target: number, max: number): Promise<void> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS n, EXISTS (SELECT 1 FROM ${table} WHERE list_id = ?1 AND user_id = ?2) AS present
       FROM ${table} WHERE list_id = ?1`,
  )
    .bind(listId, target)
    .first<{ n: number; present: number }>();
  if (!row?.present && (row?.n ?? 0) >= max) throw new ApiError("limit_reached", `This list is limited to ${max} people here.`);
}

async function currentRole(env: Env, listId: string, target: number): Promise<MemberRole | null> {
  const row = await env.DB.prepare("SELECT role FROM members WHERE list_id = ? AND user_id = ?")
    .bind(listId, target)
    .first<{ role: MemberRole }>();
  return row?.role ?? null;
}

function requireCanManage(access: Access, targetRole: MemberRole | null, newRole: MemberRole | null): void {
  if (access.role === "owner") return;
  if (targetRole === "admin" || newRole === "admin") throw new ApiError("forbidden", "Only the owner can add or remove admins.");
}

export async function putMember(request: Request, env: Env, caller: Caller, listId: string, rawUser: string) {
  const access = await requireRole(env, listId, caller.userId, "admin");
  const target = v.userId(rawUser);
  const body = await readBody(request);
  const role = body.role === undefined ? "editor" : v.memberRole(body.role);
  await requireRealOtherUser(env, caller, target, access.list.owner_id);
  const before = await currentRole(env, listId, target);
  requireCanManage(access, before, role);
  await requireRoom(env, "members", listId, target, limits.membersPerList);
  const statements = [
    env.DB.prepare(
      `INSERT INTO members (list_id, user_id, role, added_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (list_id, user_id) DO UPDATE SET role = excluded.role`,
    ).bind(listId, target, role, Date.now()),
    bumpRevision(env, listId),
    ...recordActivity(env, {
      listId,
      actorId: caller.userId,
      kind: before ? "member.changed" : "member.added",
      data: { userId: target, role, from: before },
    }),
  ];
  if (!before) statements.push(notify(env, target, listId, null, caller.userId, "list.shared", { title: access.list.title, role }));
  await env.DB.batch(statements);
  return json({ userId: target, role });
}

export async function deleteMember(_request: Request, env: Env, caller: Caller, listId: string, rawUser: string) {
  const target = v.userId(rawUser);
  const self = target === caller.userId;
  const access = await requireRole(env, listId, caller.userId, self ? "viewer" : "admin");
  if (!self) requireCanManage(access, await currentRole(env, listId, target), null);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM members WHERE list_id = ? AND user_id = ?").bind(listId, target),
    bumpRevisionIfChanged(env, listId),
    ...recordActivity(env, { listId, actorId: caller.userId, kind: "member.removed", data: { userId: target }, onlyIfChanged: true }),
  ]);
  return json({ removed: true });
}

export async function putAssignment(_request: Request, env: Env, caller: Caller, listId: string, rawUser: string) {
  const access = await requireRole(env, listId, caller.userId, "admin");
  const target = v.userId(rawUser);
  await requireRealOtherUser(env, caller, target, access.list.owner_id);
  await requireRoom(env, "assignments", listId, target, limits.assignmentsPerList);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO assignments (list_id, user_id, assigned_at) VALUES (?, ?, ?)
       ON CONFLICT (list_id, user_id) DO NOTHING`,
    ).bind(listId, target, Date.now()),
    bumpRevisionIfChanged(env, listId),
    ...recordActivity(env, { listId, actorId: caller.userId, kind: "assignment.added", data: { userId: target }, onlyIfChanged: true }),
  ]);
  return json({ userId: target, assigned: true });
}

export async function deleteAssignment(_request: Request, env: Env, caller: Caller, listId: string, rawUser: string) {
  const target = v.userId(rawUser);
  await requireRole(env, listId, caller.userId, target === caller.userId ? "viewer" : "admin");
  await env.DB.batch([
    env.DB.prepare("DELETE FROM assignments WHERE list_id = ? AND user_id = ?").bind(listId, target),
    bumpRevisionIfChanged(env, listId),
    ...recordActivity(env, { listId, actorId: caller.userId, kind: "assignment.removed", data: { userId: target }, onlyIfChanged: true }),
  ]);
  return json({ removed: true });
}
