import type { Caller, Env } from "../env";
import { ApiError, json, readBody } from "../http";

export const defaultPreferences = {
  refreshSeconds: 30,
  compact: false,
  hideCompleted: false,
  sortOrder: "manual",
  confirmDelete: true,
  notifyAssigned: true,
  notifyMentions: true,
  notifyChanges: true,
  accent: "brand",
  defaultRole: "editor",
  showHints: true,
  showTooltips: true,
  showWhatsNew: true,
  tourDone: false,
  seenVersion: "",
  uploadWarningAccepted: false,
  view: "list",
  textSizing: "fixed",
  titleSize: 1,
  bodySize: 1,
  smallSize: 1,
};

type Preferences = typeof defaultPreferences;

const rules: { [K in keyof Preferences]: (value: unknown) => boolean } = {
  refreshSeconds: (x) => x === 10 || x === 30 || x === 60 || x === 120,
  compact: (x) => typeof x === "boolean",
  hideCompleted: (x) => typeof x === "boolean",
  sortOrder: (x) => x === "manual" || x === "priority" || x === "due" || x === "recent",
  confirmDelete: (x) => typeof x === "boolean",
  notifyAssigned: (x) => typeof x === "boolean",
  notifyMentions: (x) => typeof x === "boolean",
  notifyChanges: (x) => typeof x === "boolean",
  accent: (x) => x === "brand" || x === "blue" || x === "red" || x === "green" || x === "purple" || x === "orange",
  defaultRole: (x) => x === "editor" || x === "viewer",
  showHints: (x) => typeof x === "boolean",
  showTooltips: (x) => typeof x === "boolean",
  showWhatsNew: (x) => typeof x === "boolean",
  tourDone: (x) => typeof x === "boolean",
  seenVersion: (x) => typeof x === "string" && /^[0-9.]{0,16}$/.test(x),
  uploadWarningAccepted: (x) => typeof x === "boolean",
  view: (x) => x === "list" || x === "board",
  textSizing: (x) => x === "fixed" || x === "auto",
  titleSize: (x) => x === 0.85 || x === 1 || x === 1.15 || x === 1.3,
  bodySize: (x) => x === 0.85 || x === 1 || x === 1.15 || x === 1.3,
  smallSize: (x) => x === 0.85 || x === 1 || x === 1.15 || x === 1.3,
};

export async function loadPreferences(env: Env, userId: number): Promise<Preferences> {
  const row = await env.DB.prepare("SELECT data FROM preferences WHERE user_id = ?").bind(userId).first<{ data: string }>();
  const saved = row ? (JSON.parse(row.data) as Partial<Preferences>) : {};
  const merged = { ...defaultPreferences } as Record<string, unknown>;
  for (const key of Object.keys(rules) as (keyof Preferences)[]) {
    if (saved[key] !== undefined && rules[key](saved[key])) merged[key] = saved[key];
  }
  return merged as Preferences;
}

export async function getPreferences(_request: Request, env: Env, caller: Caller): Promise<Response> {
  return json({ preferences: await loadPreferences(env, caller.userId) });
}

export async function patchPreferences(request: Request, env: Env, caller: Caller): Promise<Response> {
  const body = await readBody(request);
  const current = (await loadPreferences(env, caller.userId)) as Record<string, unknown>;
  for (const [key, value] of Object.entries(body)) {
    const rule = rules[key as keyof Preferences];
    if (!rule) throw new ApiError("bad_request", `Unknown setting: ${key}.`);
    if (!rule(value)) throw new ApiError("bad_request", `That value is not allowed for ${key}.`);
    current[key] = value;
  }
  await env.DB.prepare(
    `INSERT INTO preferences (user_id, data, updated_at) VALUES (?, ?, ?)
     ON CONFLICT (user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
  )
    .bind(caller.userId, JSON.stringify(current), Date.now())
    .run();
  return json({ preferences: current });
}
