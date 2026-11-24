import type { Env } from "./env";
import { ApiError } from "./http";

export type Role = "owner" | "admin" | "editor" | "viewer";
export type MemberRole = Exclude<Role, "owner">;

export interface ListRow {
  id: string;
  owner_id: number;
  title: string;
  share_code: string;
  revision: number;
  item_count: number;
  done_count: number;
  archived_at: number | null;
  deleted_at: number | null;
  place_id: number | null;
  created_at: number;
  updated_at: number;
}

export interface Access {
  list: ListRow;
  role: Role;
  assigned: boolean;
}

export const roleRank: Record<Role, number> = { viewer: 1, editor: 2, admin: 3, owner: 4 };

export async function resolveAccess(env: Env, listId: string, userId: number): Promise<Access | null> {
  const row = await env.DB.prepare(
    `SELECT l.*,
            m.role AS member_role,
            EXISTS (SELECT 1 FROM assignments a WHERE a.list_id = l.id AND a.user_id = ?2) AS assigned,
            EXISTS (SELECT 1 FROM visits v WHERE v.list_id = l.id AND v.user_id = ?2) AS visited,
            EXISTS (SELECT 1 FROM items i WHERE i.list_id = l.id AND i.assignee_id = ?2 AND i.deleted_at IS NULL) AS has_task
       FROM lists l
       LEFT JOIN members m ON m.list_id = l.id AND m.user_id = ?2
      WHERE l.id = ?1 AND l.deleted_at IS NULL`,
  )
    .bind(listId, userId)
    .first<ListRow & { member_role: MemberRole | null; assigned: number; visited: number; has_task: number }>();
  if (!row) return null;

  let role: Role | null = null;
  if (row.owner_id === userId) role = "owner";
  else if (row.member_role) role = row.member_role;
  else if (row.assigned || row.visited || row.has_task) role = "viewer";
  if (!role) return null;

  const { member_role: _m, assigned, visited: _v, has_task: _t, ...list } = row;
  return { list, role, assigned: assigned === 1 };
}

const needWords: Record<Role, string> = {
  owner: "Only the owner",
  admin: "Only the owner or an admin",
  editor: "Only editors",
  viewer: "Only people on this list",
};

export async function requireRole(env: Env, listId: string, userId: number, minimum: Role): Promise<Access> {
  const access = await resolveAccess(env, listId, userId);
  if (!access) throw new ApiError("not_found", "This list does not exist or you no longer have access.");
  if (roleRank[access.role] < roleRank[minimum]) throw new ApiError("forbidden", `${needWords[minimum]} can do that.`);
  return access;
}

export async function requireWritable(env: Env, listId: string, userId: number, minimum: Role): Promise<Access> {
  const access = await requireRole(env, listId, userId, minimum);
  if (access.list.archived_at !== null) {
    throw new ApiError("forbidden", "This list is archived. Unarchive it to make changes.");
  }
  return access;
}

export function bumpRevision(env: Env, listId: string): D1PreparedStatement {
  return env.DB.prepare("UPDATE lists SET revision = revision + 1, updated_at = ? WHERE id = ?").bind(Date.now(), listId);
}

export function bumpRevisionIfChanged(env: Env, listId: string): D1PreparedStatement {
  return env.DB.prepare("UPDATE lists SET revision = revision + 1, updated_at = ? WHERE id = ? AND changes() > 0").bind(
    Date.now(),
    listId,
  );
}
