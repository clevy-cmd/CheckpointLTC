import type { Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { hashKey, newKey } from "../crypto";
import { getRobloxUser } from "../roblox";
import * as v from "../validate";
import { sessionLabel, startSession } from "../sessions";

export async function register(request: Request, env: Env): Promise<Response> {
  const body = await readBody(request);
  const userId = v.userId(body.userId);

  if (env.requireVerification === "true") {
    throw new ApiError("verification_required", "Log in with Roblox from the plugin.");
  }

  const profile = await getRobloxUser(userId);
  if (!profile) throw new ApiError("bad_request", "That Roblox account does not exist.");

  const key = newKey();
  const keyHash = await hashKey(key);
  const now = Date.now();
  const result = await env.DB.prepare(
    "INSERT OR IGNORE INTO users (user_id, key_hash, verified, created_at, last_seen_at) VALUES (?, ?, 0, ?, ?)",
  )
    .bind(userId, keyHash, now, now)
    .run();
  if (result.meta.changes !== 1) {
    throw new ApiError("already_registered", "This Roblox account is already set up.");
  }
  await env.DB.batch(startSession(env, userId, keyHash, sessionLabel(body.label), now));
  return json({ userId, key, verified: false }, 201);
}
