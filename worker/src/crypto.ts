import { idAlphabet, idLength, keyBytes, keyPrefix, shareCodeAlphabet, shareCodeLength } from "./config";

function randomString(alphabet: string, length: number): string {
  const limit = 256 - (256 % alphabet.length);
  let out = "";
  while (out.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length * 2));
    for (const b of bytes) {
      if (b < limit) out += alphabet[b % alphabet.length];
      if (out.length === length) break;
    }
  }
  return out;
}

export const newId = (): string => randomString(idAlphabet, idLength);
export const newShareCode = (): string => randomString(shareCodeAlphabet, shareCodeLength);

export const newLoginCode = (): string => randomString(shareCodeAlphabet, 8);

export function base64Url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function randomToken(): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export function newKey(): string {
  return keyPrefix + base64Url(crypto.getRandomValues(new Uint8Array(keyBytes)));
}

export async function hashKey(key: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
