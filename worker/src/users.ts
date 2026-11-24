import type { Caller, Env } from "./env";
import { ApiError, json } from "./http";
import { limits } from "./config";

export interface PublicUser {
  userId: number;
  name: string;
  displayName: string;
}

async function robloxPost(url: string, body: unknown): Promise<unknown> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { accept: "application/json", "content-type": "application/json", "user-agent": "CheckpointLTC/1" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(limits.robloxLookupTimeoutMs),
      });
      if (response.ok) return response.json();
    } catch {
      continue;
    }
    await new Promise((resolve) => setTimeout(resolve, 400 * (attempt + 1)));
  }
  throw new ApiError("unavailable", "Roblox could not be reached. Try again in a moment.");
}

interface RobloxEntry {
  id?: unknown;
  name?: unknown;
  displayName?: unknown;
}

function toUsers(data: unknown): PublicUser[] {
  const list = (data as { data?: RobloxEntry[] })?.data ?? [];
  return list
    .filter((e) => typeof e.id === "number" && typeof e.name === "string")
    .map((e) => ({ userId: e.id as number, name: e.name as string, displayName: String(e.displayName ?? e.name) }));
}

async function remember(env: Env, users: PublicUser[]): Promise<void> {
  if (users.length === 0) return;
  const now = Date.now();
  await env.DB.batch(
    users.map((u) =>
      env.DB.prepare(
        `INSERT INTO roblox_users (user_id, name, display_name, fetched_at) VALUES (?, ?, ?, ?)
         ON CONFLICT (user_id) DO UPDATE SET name = excluded.name, display_name = excluded.display_name, fetched_at = excluded.fetched_at`,
      ).bind(u.userId, u.name, u.displayName, now),
    ),
  );
}

export async function usersById(env: Env, ids: number[]): Promise<Map<number, PublicUser>> {
  const unique = [...new Set(ids)].filter((id) => Number.isSafeInteger(id) && id > 0).slice(0, 100);
  const found = new Map<number, PublicUser>();
  if (unique.length === 0) return found;
  const cached = await env.DB.prepare(
    `SELECT user_id, name, display_name, fetched_at FROM roblox_users WHERE user_id IN (${unique.map(() => "?").join(",")})`,
  )
    .bind(...unique)
    .all<{ user_id: number; name: string; display_name: string; fetched_at: number }>();
  const fresh = Date.now() - limits.userCacheMs;
  for (const r of cached.results) {
    found.set(r.user_id, { userId: r.user_id, name: r.name, displayName: r.display_name });
  }
  const missing = unique.filter((id) => {
    const row = cached.results.find((r) => r.user_id === id);
    return !row || row.fetched_at < fresh;
  });
  if (missing.length > 0) {
    try {
      const users = toUsers(await robloxPost("https://users.roblox.com/v1/users", { userIds: missing, excludeBannedUsers: false }));
      await remember(env, users);
      for (const u of users) found.set(u.userId, u);
    } catch (err) {
      if (!(err instanceof ApiError)) throw err;
    }
  }
  return found;
}

export async function userExists(env: Env, userId: number): Promise<boolean> {
  const cached = await env.DB.prepare("SELECT 1 AS ok FROM roblox_users WHERE user_id = ?").bind(userId).first<{ ok: number }>();
  if (cached) return true;
  const users = toUsers(await robloxPost("https://users.roblox.com/v1/users", { userIds: [userId], excludeBannedUsers: false }));
  await remember(env, users);
  return users.some((u) => u.userId === userId);
}

export async function userByName(env: Env, username: string): Promise<PublicUser | null> {
  const cached = await env.DB.prepare(
    "SELECT user_id, name, display_name, fetched_at FROM roblox_users WHERE name = ? COLLATE NOCASE",
  )
    .bind(username)
    .first<{ user_id: number; name: string; display_name: string; fetched_at: number }>();
  if (cached && cached.fetched_at > Date.now() - limits.userCacheMs) {
    return { userId: cached.user_id, name: cached.name, displayName: cached.display_name };
  }
  const users = toUsers(await robloxPost("https://users.roblox.com/v1/usernames/users", { usernames: [username], excludeBannedUsers: true }));
  await remember(env, users);
  return users[0] ?? null;
}

export async function lookupUsers(request: Request, env: Env, _caller: Caller): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const username = params.get("username");
  if (username !== null) {
    if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) throw new ApiError("bad_request", "That is not a valid Roblox username.");
    const user = await userByName(env, username);
    if (!user) throw new ApiError("not_found", "No Roblox account has that username.");
    return json({ users: [user] });
  }
  const ids = (params.get("ids") ?? "")
    .split(",")
    .filter((s) => /^\d{1,19}$/.test(s))
    .map(Number);
  if (ids.length === 0) throw new ApiError("bad_request", "Pass ids or username.");
  if (ids.length > 100) throw new ApiError("bad_request", "Up to 100 ids at a time.");
  const users = await usersById(env, ids);
  return json({ users: [...users.values()] });
}
