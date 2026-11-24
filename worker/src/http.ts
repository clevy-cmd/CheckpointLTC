import { limits } from "./config";

export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "forbidden"
  | "not_found"
  | "conflict"
  | "already_registered"
  | "verification_required"
  | "verification_failed"
  | "login_expired"
  | "licence_required"
  | "banned"
  | "limit_reached"
  | "rate_limited"
  | "cooldown"
  | "uploads_blocked"
  | "too_large"
  | "upgrade_required"
  | "unavailable"
  | "internal";

const statusFor: Record<ErrorCode, number> = {
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  already_registered: 409,
  verification_required: 403,
  verification_failed: 403,
  login_expired: 410,
  licence_required: 403,
  banned: 403,
  limit_reached: 422,
  rate_limited: 429,
  cooldown: 429,
  uploads_blocked: 403,
  too_large: 413,
  upgrade_required: 426,
  unavailable: 503,
  internal: 500,
};

export class ApiError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
  get status(): number {
    return statusFor[this.code];
  }
}

const baseHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "strict-transport-security": "max-age=63072000; includeSubDomains",
};

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: baseHeaders });
}

export function errorResponse(err: ApiError): Response {
  return json({ error: { code: err.code, message: err.message, ...err.extra } }, err.status);
}

export async function readBody(request: Request, maxBytes: number = limits.maxBodyBytes): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new ApiError("bad_request", "Request body is too large.");
  const raw = await request.text();
  if (raw.length === 0) return {};
  if (raw.length > maxBytes) throw new ApiError("bad_request", "Request body is too large.");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ApiError("bad_request", "Request body is not valid JSON.");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new ApiError("bad_request", "Request body must be a JSON object.");
  }
  return parsed as Record<string, unknown>;
}
