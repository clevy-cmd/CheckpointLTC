import { ApiError } from "./http";
import { shareCodeAlphabet, shareCodeLength } from "./config";

export function userId(value: unknown, field = "userId"): number {
  const n = typeof value === "string" && /^\d{1,19}$/.test(value) ? Number(value) : value;
  if (typeof n !== "number" || !Number.isSafeInteger(n) || n <= 0) {
    throw new ApiError("bad_request", `${field} must be a positive Roblox UserId.`);
  }
  return n;
}

export function text(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string") throw new ApiError("bad_request", `${field} must be text.`);
  const cleaned = value.replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
  if (cleaned.length === 0) throw new ApiError("bad_request", `${field} cannot be empty.`);
  if (cleaned.length > maxLength) {
    throw new ApiError("bad_request", `${field} must be ${maxLength} characters or fewer.`);
  }
  return cleaned;
}

export function bool(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw new ApiError("bad_request", `${field} must be true or false.`);
  return value;
}

export function positiveInt(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new ApiError("bad_request", `${field} must be a whole number.`);
  }
  return value;
}

const codePattern = new RegExp(`^[${shareCodeAlphabet}]{${shareCodeLength}}$`);

export function shareCode(value: unknown): string {
  if (typeof value !== "string") throw new ApiError("bad_request", "code must be text.");
  const normalized = value.replace(/[\s_.]+/g, "").toUpperCase();
  if (!codePattern.test(normalized)) throw new ApiError("bad_request", "That does not look like a list code.");
  return normalized;
}

export function role(value: unknown): "editor" | "viewer" {
  if (value !== "editor" && value !== "viewer") throw new ApiError("bad_request", "role must be editor or viewer.");
  return value;
}

export function memberRole(value: unknown): "admin" | "editor" | "viewer" {
  if (value !== "admin" && value !== "editor" && value !== "viewer") {
    throw new ApiError("bad_request", "role must be admin, editor or viewer.");
  }
  return value;
}

export function optionalText(value: unknown, field: string, maxLength: number): string | null {
  if (value === null || value === "") return null;
  if (typeof value !== "string") throw new ApiError("bad_request", `${field} must be text.`);
  const cleaned = value.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000b-\u001f\u007f]+/g, " ").trim();
  if (cleaned.length > maxLength) throw new ApiError("bad_request", `${field} must be ${maxLength} characters or fewer.`);
  return cleaned === "" ? null : cleaned;
}

export function priority(value: unknown): number {
  if (value !== 0 && value !== 1 && value !== 2 && value !== 3) {
    throw new ApiError("bad_request", "priority must be 0, 1, 2 or 3.");
  }
  return value;
}

export function timestamp(value: unknown, field: string): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value > 32503680000000) {
    throw new ApiError("bad_request", `${field} must be a time in milliseconds or null.`);
  }
  return value;
}

export function oneOf<T extends string>(value: unknown, field: string, allowed: readonly T[]): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new ApiError("bad_request", `${field} must be one of: ${allowed.join(", ")}.`);
  }
  return value as T;
}

export interface TaskLink {
  kind: "instance" | "script";
  path: string;
  guid: string | null;
  line: number | null;
  placeId: number | null;
}

export function link(value: unknown, maxLength: number): TaskLink | null {
  if (value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) throw new ApiError("bad_request", "link must be an object or null.");
  const raw = value as Record<string, unknown>;
  const kind = oneOf(raw.kind, "link.kind", ["instance", "script"] as const);
  const path = text(raw.path, "link.path", maxLength);
  const guid = raw.guid === undefined || raw.guid === null ? null : text(raw.guid, "link.guid", 64);
  let line: number | null = null;
  if (raw.line !== undefined && raw.line !== null) {
    if (typeof raw.line !== "number" || !Number.isSafeInteger(raw.line) || raw.line < 1 || raw.line > 1_000_000) {
      throw new ApiError("bad_request", "link.line must be a line number.");
    }
    line = raw.line;
  }
  const placeId = raw.placeId === undefined || raw.placeId === null ? null : userId(raw.placeId, "link.placeId");
  return { kind, path, guid, line, placeId };
}

export function idText(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^[a-z0-9]{6,32}$/.test(value)) throw new ApiError("bad_request", `${field} is not a valid id.`);
  return value;
}

export function userIds(value: unknown, field: string, max: number): number[] {
  if (!Array.isArray(value)) throw new ApiError("bad_request", `${field} must be a list of UserIds.`);
  if (value.length > max) throw new ApiError("bad_request", `${field} can hold up to ${max} people.`);
  return [...new Set(value.map((id) => userId(id, field)))];
}
