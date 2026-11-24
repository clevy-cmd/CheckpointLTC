import type { Env } from "./env";
import { limits } from "./config";
import { ApiError } from "./http";
import { base64Url } from "./crypto";

const base = "https://apis.roblox.com/oauth/v1";

export const isPaid = (env: Env): boolean => Boolean(env.pluginAssetId);

export function oauthConfigured(env: Env): boolean {
  const ready = Boolean(env.ROBLOX_CLIENT_ID && env.ROBLOX_CLIENT_SECRET && env.publicOrigin);
  return isPaid(env) ? ready && Boolean(env.TOKEN_KEY) : ready;
}

export function redirectUri(env: Env): string {
  return `${env.publicOrigin}/oauth/callback`;
}

async function pkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

export async function authorizeUrl(env: Env, state: string, verifier: string): Promise<string> {
  const params = new URLSearchParams({
    client_id: env.ROBLOX_CLIENT_ID,
    redirect_uri: redirectUri(env),
    scope: isPaid(env) ? "openid user.inventory-item:read" : "openid",
    response_type: "code",
    state,
    code_challenge: await pkceChallenge(verifier),
    code_challenge_method: "S256",
  });
  return `${base}/authorize?${params}`;
}

export async function robloxFetch(url: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(limits.robloxOAuthTimeoutMs) });
  } catch {
    throw new ApiError("unavailable", "Roblox could not be reached. Try again in a moment.");
  }
}

export interface Tokens {
  accessToken: string;
  refreshToken: string | null;
}

async function tokenRequest(env: Env, fields: Record<string, string>): Promise<Tokens> {
  const response = await robloxFetch(`${base}/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: new URLSearchParams({ ...fields, client_id: env.ROBLOX_CLIENT_ID, client_secret: env.ROBLOX_CLIENT_SECRET }),
  });
  if (response.status >= 500) throw new ApiError("unavailable", "Roblox could not be reached. Try again in a moment.");
  const data = response.ok ? ((await response.json()) as { access_token?: unknown; refresh_token?: unknown }) : {};
  if (typeof data.access_token !== "string") {
    console.warn("roblox token request failed", response.status);
    throw new ApiError("verification_failed", "Roblox did not accept the login. Start again from Studio.");
  }
  return {
    accessToken: data.access_token,
    refreshToken: typeof data.refresh_token === "string" ? data.refresh_token : null,
  };
}

export const exchangeCode = (env: Env, code: string, verifier: string): Promise<Tokens> =>
  tokenRequest(env, { grant_type: "authorization_code", code, code_verifier: verifier, redirect_uri: redirectUri(env) });

export const refreshTokens = (env: Env, refreshToken: string): Promise<Tokens> =>
  tokenRequest(env, { grant_type: "refresh_token", refresh_token: refreshToken });

export async function userIdFromToken(accessToken: string): Promise<number> {
  const response = await robloxFetch(`${base}/userinfo`, {
    headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" },
  });
  const info = response.ok ? ((await response.json()) as { sub?: unknown }) : {};
  const userId = Number(info.sub);
  if (!Number.isSafeInteger(userId) || userId <= 0) {
    throw new ApiError("verification_failed", "Roblox did not return an account. Start again from Studio.");
  }
  return userId;
}

export async function revoke(env: Env, refreshToken: string): Promise<void> {
  await robloxFetch(`${base}/token/revoke`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      token: refreshToken,
      client_id: env.ROBLOX_CLIENT_ID,
      client_secret: env.ROBLOX_CLIENT_SECRET,
    }),
  }).catch(() => undefined);
}
