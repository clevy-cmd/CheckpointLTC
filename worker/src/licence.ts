import type { Env } from "./env";
import { limits } from "./config";
import { ApiError } from "./http";
import { base64Url } from "./crypto";
import { refreshTokens, robloxFetch } from "./oauth";
import { endAllSessions } from "./sessions";

export function storeUrl(env: Env): string {
  return env.pluginAssetId ? `https://create.roblox.com/store/asset/${env.pluginAssetId}` : "";
}

export async function ownsPlugin(env: Env, accessToken: string, userId: number): Promise<boolean> {
  const query = new URLSearchParams({ filter: `assetIds=${env.pluginAssetId}`, maxPageSize: "10" });
  for (let page = 0; page < 3; page++) {
    const response = await robloxFetch(`https://apis.roblox.com/cloud/v2/users/${userId}/inventory-items?${query}`, {
      headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" },
    });
    if (!response.ok) {
      console.warn("roblox inventory check failed", response.status);
      if (response.status === 429 || response.status >= 500) {
        throw new ApiError("unavailable", "Couldn't check your purchase with Roblox. Try again in a moment.");
      }
      throw new ApiError("verification_failed", "Roblox wouldn't let me check your purchase. Log in with Roblox again.");
    }
    const data = (await response.json()) as {
      inventoryItems?: { assetDetails?: { assetId?: string } }[];
      nextPageToken?: string;
    };
    if (data.inventoryItems?.some((item) => item.assetDetails?.assetId === env.pluginAssetId)) return true;
    if (!data.nextPageToken) return false;
    query.set("pageToken", data.nextPageToken);
  }
  return false;
}

async function aesKey(env: Env): Promise<CryptoKey> {
  const raw = Uint8Array.from(atob(env.TOKEN_KEY), (c) => c.charCodeAt(0));
  if (raw.length !== 32) throw new Error("TOKEN_KEY must be 32 bytes, base64");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function seal(env: Env, text: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(env), new TextEncoder().encode(text));
  const out = new Uint8Array(12 + sealed.byteLength);
  out.set(iv);
  out.set(new Uint8Array(sealed), 12);
  return base64Url(out);
}

async function unseal(env: Env, sealed: string): Promise<string> {
  const padded = sealed.replace(/-/g, "+").replace(/_/g, "/");
  const bytes = Uint8Array.from(atob(padded + "=".repeat((4 - (padded.length % 4)) % 4)), (c) => c.charCodeAt(0));
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, await aesKey(env), bytes.slice(12));
  return new TextDecoder().decode(plain);
}

interface LicenceRow {
  user_id: number;
  roblox_refresh: string | null;
  licence_checked_at: number | null;
}

export async function enforceLicence(env: Env, row: LicenceRow): Promise<void> {
  if (!row.roblox_refresh || row.licence_checked_at === null) {
    throw new ApiError("unauthorized", "Log in with Roblox again so I can check your license.");
  }
  const now = Date.now();
  if (now - row.licence_checked_at < limits.licenceRecheckMs) return;

  const claimed = await env.DB.prepare(
    "UPDATE users SET licence_checked_at = ? WHERE user_id = ? AND licence_checked_at = ?",
  )
    .bind(now, row.user_id, row.licence_checked_at)
    .run();
  if (claimed.meta.changes !== 1) return;

  let owned: boolean;
  try {
    const tokens = await refreshTokens(env, await unseal(env, row.roblox_refresh));
    if (tokens.refreshToken) {
      await env.DB.prepare("UPDATE users SET roblox_refresh = ? WHERE user_id = ?")
        .bind(await seal(env, tokens.refreshToken), row.user_id)
        .run();
    }
    owned = await ownsPlugin(env, tokens.accessToken, row.user_id);
  } catch (err) {
    if (err instanceof ApiError && err.code === "unavailable") {
      await env.DB.prepare("UPDATE users SET licence_checked_at = ? WHERE user_id = ?")
        .bind(now - limits.licenceRecheckMs + limits.licenceRetryMs, row.user_id)
        .run();
      return;
    }
    await signOut(env, row.user_id);
    throw new ApiError("unauthorized", "Log in with Roblox again so I can check your license.");
  }

  if (!owned) {
    await signOut(env, row.user_id);
    throw new ApiError("licence_required", "This Roblox account doesn't own CheckpointLTC anymore.");
  }
}

async function signOut(env: Env, userId: number): Promise<void> {
  await env.DB.batch([
    ...endAllSessions(env, userId),
    env.DB.prepare("UPDATE users SET roblox_refresh = NULL, licence_checked_at = NULL WHERE user_id = ?").bind(userId),
  ]);
}
