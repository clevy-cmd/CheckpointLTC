import type { Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { hashKey, newKey, newLoginCode, randomToken } from "../crypto";
import { bannedMessage, limits } from "../config";
import { authorizeUrl, exchangeCode, isPaid, oauthConfigured, revoke, userIdFromToken } from "../oauth";
import { ownsPlugin, seal, storeUrl } from "../licence";
import { escapeHtml, messagePage, page } from "../pages";
import * as v from "../validate";
import { activeBan, blocksLogin, sessionLabel, startSession } from "../sessions";

interface Session {
  code: string;
  oauth_state: string;
  pkce_verifier: string;
  studio_user_id: number;
  user_id: number | null;
  error: string | null;
  error_code: string | null;
  roblox_refresh: string | null;
  expires_at: number;
}

const formatCode = (code: string): string => `${code.slice(0, 4)} ${code.slice(4)}`;

export async function start(request: Request, env: Env): Promise<Response> {
  if (!oauthConfigured(env)) throw new ApiError("unavailable", "Log in with Roblox is not set up on the server yet.");
  const body = await readBody(request);
  const studioUserId = v.userId(body.userId);

  const now = Date.now();
  const code = newLoginCode();
  const pollToken = randomToken();
  const expiresAt = now + limits.loginTtlMs;

  await env.DB.batch([
    env.DB.prepare("DELETE FROM login_sessions WHERE expires_at < ?").bind(now),
    env.DB.prepare(
      `INSERT INTO login_sessions (code, poll_hash, oauth_state, pkce_verifier, studio_user_id, expires_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(code, await hashKey(pollToken), randomToken(), randomToken(), studioUserId, expiresAt, now),
  ]);

  return json({
    code: formatCode(code),
    url: `${env.publicOrigin}/login/${code}`,
    pollToken,
    expiresAt,
    pollSeconds: limits.loginPollSeconds,
  });
}

export async function poll(request: Request, env: Env): Promise<Response> {
  const body = await readBody(request);
  const code = v.shareCode(body.code);
  if (typeof body.pollToken !== "string" || body.pollToken.length > 64) {
    throw new ApiError("bad_request", "pollToken is missing.");
  }
  const pollHash = await hashKey(body.pollToken);

  const session = await env.DB.prepare("SELECT * FROM login_sessions WHERE code = ? AND poll_hash = ?")
    .bind(code, pollHash)
    .first<Session>();
  if (!session || session.expires_at < Date.now()) {
    throw new ApiError("login_expired", "That login expired. Press Log in with Roblox again.");
  }
  if (session.error) {
    await env.DB.prepare("DELETE FROM login_sessions WHERE code = ?").bind(code).run();
    const errorCode = session.error_code === "licence_required" || session.error_code === "banned" ? session.error_code : "verification_failed";
    throw new ApiError(errorCode, session.error);
  }
  if (session.user_id === null) return json({ status: "pending" });

  const claimed = await env.DB.prepare("DELETE FROM login_sessions WHERE code = ? AND poll_hash = ?")
    .bind(code, pollHash)
    .run();
  if (claimed.meta.changes !== 1) throw new ApiError("login_expired", "That login was already used.");

  if (blocksLogin(await activeBan(env, session.user_id))) throw new ApiError("banned", bannedMessage);

  const key = newKey();
  const keyHash = await hashKey(key);
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO users (user_id, key_hash, verified, roblox_refresh, licence_checked_at, created_at, last_seen_at)
       VALUES (?, ?, 1, ?, ?, ?, ?)
       ON CONFLICT (user_id) DO UPDATE SET key_hash = excluded.key_hash, verified = 1, roblox_refresh = excluded.roblox_refresh,
         licence_checked_at = excluded.licence_checked_at, last_seen_at = excluded.last_seen_at`,
    ).bind(session.user_id, keyHash, session.roblox_refresh, session.roblox_refresh ? now : null, now, now),
    ...startSession(env, session.user_id, keyHash, sessionLabel(body.label), now),
  ]);
  return json({ status: "done", userId: session.user_id, key });
}

const sharedNote = (env: Env): string =>
  isPaid(env)
    ? "Roblox tells CheckpointLTC your UserId and lets it check you own the plugin. Never your password, and it can't change anything on your account."
    : "Roblox tells CheckpointLTC your UserId and nothing else. Never your password, and no access to your account.";

const expiredPage = () =>
  messagePage("This link has expired", "Go back to Roblox Studio and press Log in with Roblox again.", true, 410);

export async function loginPage(_request: Request, env: Env, code: string): Promise<Response> {
  const session = await env.DB.prepare("SELECT * FROM login_sessions WHERE code = ?").bind(code).first<Session>();
  if (!session || session.expires_at < Date.now()) return expiredPage();
  if (session.error) return messagePage("Login failed", session.error, true);
  if (session.user_id !== null) return messagePage("You are logged in", "Go back to Roblox Studio.", false);

  const link = await authorizeUrl(env, session.oauth_state, session.pkce_verifier);
  return page(
    "Log in",
    `<h1>Log in to CheckpointLTC</h1>
<p>Check this code matches the one showing in your Roblox Studio panel.</p>
<div class="code">${escapeHtml(formatCode(code))}</div>
<a class="button" href="${escapeHtml(link)}">Continue with Roblox</a>
<small>Only continue if you pressed Log in with Roblox in Studio yourself just now. Never use a login link someone sent you. ${escapeHtml(sharedNote(env))}</small>`,
  );
}

export async function callback(request: Request, env: Env): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const state = params.get("state") ?? "";
  const session = state
    ? await env.DB.prepare("SELECT * FROM login_sessions WHERE oauth_state = ?").bind(state).first<Session>()
    : null;
  if (!session || session.expires_at < Date.now()) return expiredPage();
  if (session.user_id !== null || session.error) return expiredPage();

  const fail = async (message: string, code = "verification_failed"): Promise<Response> => {
    await env.DB.prepare("UPDATE login_sessions SET error = ?, error_code = ?, pkce_verifier = '' WHERE code = ?")
      .bind(message, code, session.code)
      .run();
    return messagePage("Login failed", `${message} Then press Log in with Roblox in Studio again.`, true);
  };

  const authCode = params.get("code");
  if (!authCode) return fail("The Roblox login was cancelled.");

  let userId: number;
  let refresh: string | null = null;
  try {
    const tokens = await exchangeCode(env, authCode, session.pkce_verifier);
    userId = await userIdFromToken(tokens.accessToken);
    if (blocksLogin(await activeBan(env, userId))) {
      if (tokens.refreshToken) await revoke(env, tokens.refreshToken);
      await fail(bannedMessage, "banned");
      return messagePage("Login blocked", bannedMessage, true, 403);
    }
    if (userId !== session.studio_user_id) {
      if (tokens.refreshToken) await revoke(env, tokens.refreshToken);
      return fail("You logged in to a different Roblox account from the one signed in to Studio. Use the same account.");
    }
    if (isPaid(env)) {
      if (!(await ownsPlugin(env, tokens.accessToken, userId))) {
        if (tokens.refreshToken) await revoke(env, tokens.refreshToken);
        await fail("This Roblox account doesn't own CheckpointLTC yet.", "licence_required");
        return notOwnedPage(env);
      }
      if (!tokens.refreshToken) return fail("Roblox didn't give me what I need to check your license.");
      refresh = await seal(env, tokens.refreshToken);
    } else if (tokens.refreshToken) {
      await revoke(env, tokens.refreshToken);
    }
  } catch (err) {
    if (err instanceof ApiError) return fail(err.message);
    throw err;
  }

  const done = await env.DB.prepare(
    `UPDATE login_sessions SET user_id = ?, roblox_refresh = ?, pkce_verifier = ''
      WHERE code = ? AND user_id IS NULL AND error IS NULL`,
  )
    .bind(userId, refresh, session.code)
    .run();
  if (done.meta.changes !== 1) return expiredPage();
  return messagePage("You are logged in", "Go back to Roblox Studio. The panel finishes on its own.", false);
}

function notOwnedPage(env: Env): Response {
  const url = storeUrl(env);
  return page(
    "Get CheckpointLTC",
    `<h1>You don't own CheckpointLTC yet</h1>
<p>Get it on the Creator Store with this same Roblox account, then press Log in with Roblox in Studio again.</p>
<a class="button" href="${escapeHtml(url)}">Get it on the Creator Store</a>
<small>Already bought it? Make sure you logged in with the account you bought it on.</small>`,
  );
}
