import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";
import { newId } from "../crypto";
import { limits, uploadTypes } from "../config";
import * as v from "../validate";
import { loadPreferences } from "./preferences";

export interface UploadRow {
  id: string;
  user_id: number;
  name: string;
  extension: string;
  size: number;
  parts: number;
  received: number;
  status: "pending" | "complete" | "clean" | "held" | "rejected" | "evidence" | "sent";
  verdict: string | null;
  scores: string | null;
  review_hash: string | null;
  keep: number;
  created_at: number;
  expires_at: number | null;
}

export const fileKey = (id: string) => `files/${id}`;
const partKey = (id: string, part: number) => `tmp/${id}/${part}`;

export function requireUploadsAllowed(caller: Caller): void {
  if (caller.banLevel) throw new ApiError("uploads_blocked", "File uploads are disabled on this account.");
}

const sizeText = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

export async function startUpload(request: Request, env: Env, caller: Caller): Promise<Response> {
  requireUploadsAllowed(caller);
  const prefs = await loadPreferences(env, caller.userId);
  if (!prefs.uploadWarningAccepted) throw new ApiError("forbidden", "Read the upload warning and tick I understand first.");
  const body = await readBody(request);
  const name = v.text(body.name, "File name", 120).replace(/[\\/:*?"<>|]+/g, "_");
  const extension = (/\.([A-Za-z0-9]{1,5})$/.exec(name)?.[1] ?? "").toLowerCase();
  if (!uploadTypes[extension]) throw new ApiError("bad_request", "Only mp4, mov, png, jpg and txt files can be attached.");
  if (typeof body.size !== "number" || !Number.isSafeInteger(body.size) || body.size <= 0) {
    throw new ApiError("bad_request", "size must be the file size in bytes.");
  }
  if (body.size > limits.uploadMaxBytes) {
    throw new ApiError("too_large", `That file is ${sizeText(body.size)}. Files can be up to ${sizeText(limits.uploadMaxBytes)}.`);
  }

  const stale = await env.DB.prepare("SELECT id, parts FROM uploads WHERE user_id = ? AND status = 'pending'")
    .bind(caller.userId)
    .all<{ id: string; parts: number }>();
  for (const old of stale.results) await discardParts(env, old.id, old.parts);
  const id = newId();
  const parts = Math.ceil(body.size / limits.uploadChunkBytes);
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM uploads WHERE user_id = ? AND status = 'pending'").bind(caller.userId),
    env.DB.prepare(
      "INSERT INTO uploads (id, user_id, name, extension, size, parts, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)",
    ).bind(id, caller.userId, name, extension, body.size, parts, now, now + limits.uploadPendingMs),
  ]);
  return json({ uploadId: id, parts, chunkBytes: limits.uploadChunkBytes }, 201);
}

function decodeBase64(text: string): Uint8Array {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw new ApiError("bad_request", "data must be base64.");
  let binary: string;
  try {
    binary = atob(text);
  } catch {
    throw new ApiError("bad_request", "data must be base64.");
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function putPart(request: Request, env: Env, caller: Caller, uploadId: string, rawPart: string): Promise<Response> {
  requireUploadsAllowed(caller);
  const part = Number(rawPart);
  const upload = await env.DB.prepare("SELECT * FROM uploads WHERE id = ? AND user_id = ?").bind(uploadId, caller.userId).first<UploadRow>();
  if (!upload || upload.status !== "pending") throw new ApiError("not_found", "That upload expired. Attach the file again.");
  if (part !== upload.received) throw new ApiError("bad_request", `Send part ${upload.received} next.`);
  const body = await readBody(request, limits.uploadChunkBodyBytes);
  if (typeof body.data !== "string") throw new ApiError("bad_request", "data is missing.");
  const bytes = decodeBase64(body.data);
  const last = part === upload.parts - 1;
  const expected = last ? upload.size - limits.uploadChunkBytes * part : limits.uploadChunkBytes;
  if (bytes.length !== expected) throw new ApiError("bad_request", "That part is the wrong size. Attach the file again.");
  await env.UPLOADS.put(partKey(uploadId, part), bytes);
  const done = await env.DB.prepare(
    `UPDATE uploads SET received = received + 1, status = CASE WHEN received + 1 = parts THEN 'complete' ELSE status END
      WHERE id = ? AND received = ?`,
  )
    .bind(uploadId, part)
    .run();
  if (done.meta.changes !== 1) throw new ApiError("conflict", "That part was already sent.");
  return json({ received: part + 1, parts: upload.parts, complete: last });
}

export async function discardParts(env: Env, id: string, parts: number): Promise<void> {
  const keys = Array.from({ length: parts }, (_, n) => partKey(id, n));
  for (let start = 0; start < keys.length; start += 1000) await env.UPLOADS.delete(keys.slice(start, start + 1000));
}

export function headerMatches(extension: string, bytes: Uint8Array): boolean {
  const at = (offset: number, values: number[]) => values.every((value, i) => bytes[offset + i] === value);
  const ascii = (offset: number, text: string) => at(offset, [...text].map((c) => c.charCodeAt(0)));
  switch (extension) {
    case "png":
      return at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case "jpg":
    case "jpeg":
      return at(0, [0xff, 0xd8, 0xff]);
    case "mp4":
      return ascii(4, "ftyp");
    case "mov":
      return ["ftyp", "moov", "mdat", "wide", "free", "skip", "pnot"].some((atom) => ascii(4, atom));
    case "txt": {
      if (bytes.includes(0)) return false;
      try {
        new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
        return true;
      } catch {
        return false;
      }
    }
    default:
      return false;
  }
}

export async function assemble(env: Env, upload: UploadRow): Promise<Uint8Array> {
  const bytes = new Uint8Array(upload.size);
  let offset = 0;
  for (let part = 0; part < upload.parts; part++) {
    const object = await env.UPLOADS.get(partKey(upload.id, part));
    if (!object) throw new ApiError("not_found", "That upload expired. Attach the file again.");
    const chunk = new Uint8Array(await object.arrayBuffer());
    if (offset + chunk.length > bytes.length) throw new ApiError("bad_request", "That file did not upload correctly.");
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  if (offset !== upload.size) throw new ApiError("bad_request", "That file did not upload correctly. Attach it again.");
  if (!headerMatches(upload.extension, bytes)) {
    throw new ApiError("bad_request", `That file is not a real ${upload.extension} file. Only mp4, mov, png, jpg and txt files can be attached.`);
  }
  await env.UPLOADS.put(fileKey(upload.id), bytes, { httpMetadata: { contentType: uploadTypes[upload.extension].mime } });
  await discardParts(env, upload.id, upload.parts);
  return bytes;
}

export async function cancelUpload(_request: Request, env: Env, caller: Caller, uploadId: string): Promise<Response> {
  const upload = await env.DB.prepare("SELECT * FROM uploads WHERE id = ? AND user_id = ?").bind(uploadId, caller.userId).first<UploadRow>();
  if (upload && (upload.status === "pending" || upload.status === "complete")) {
    await discardParts(env, upload.id, upload.parts);
    await env.DB.prepare("DELETE FROM uploads WHERE id = ?").bind(uploadId).run();
  }
  return json({ removed: true });
}
