import type { Caller, Env } from "./env";
import { ApiError, errorResponse, json } from "./http";
import { authenticate, enforceRateLimit } from "./auth";
import * as accounts from "./routes/accounts";
import * as login from "./routes/login";
import * as legal from "./legal";
import { logo } from "./pages";
import { serveMedia } from "./media";
import * as lists from "./routes/lists";
import * as items from "./routes/items";
import * as sharing from "./routes/sharing";
import * as preferences from "./routes/preferences";
import * as comments from "./routes/comments";
import * as uploads from "./routes/uploads";
import * as submissions from "./routes/submissions";
import * as review from "./routes/review";
import * as games from "./routes/games";
import * as trashRoutes from "./routes/trash";
import { me } from "./routes/me";
import { undoLast } from "./routes/undo";
import { listActivity } from "./activity";
import { endCurrentSession, endSession, listSessions } from "./sessions";
import { lookupUsers } from "./users";
import { listNotifications, readNotifications } from "./notifications";
import { cleanup } from "./cleanup";
import { shareCodeAlphabet } from "./config";
import { isPaid } from "./oauth";
import { storeUrl } from "./licence";

type Authed = (request: Request, env: Env, caller: Caller, ...params: string[]) => Promise<Response>;
type Open = (request: Request, env: Env, ...params: string[]) => Promise<Response>;

interface Route {
  method: string;
  pattern: RegExp;
  auth: boolean;
  handler: Authed | Open;
  limiter?: "poll" | "none";
  skipIpLimit?: boolean;
}

const id = "([a-z0-9]{6,32})";
const uid = "(\\d{1,19})";
const loginCode = `([${shareCodeAlphabet}]{8})`;
const token = "([A-Za-z0-9_-]{30,60})";
const part = "(\\d{1,3})";
const at = (path: string) => new RegExp(`^${path}$`);

const routes: Route[] = [
  { method: "GET", pattern: at("/v1/meta"), auth: false, handler: meta, limiter: "none" },
  { method: "POST", pattern: at("/v1/register"), auth: false, handler: accounts.register },
  { method: "POST", pattern: at("/v1/login/start"), auth: false, handler: login.start },
  { method: "POST", pattern: at("/v1/login/poll"), auth: false, handler: login.poll, limiter: "poll" },
  { method: "GET", pattern: at(`/login/${loginCode}`), auth: false, handler: login.loginPage },
  { method: "GET", pattern: at("/oauth/callback"), auth: false, handler: login.callback },
  { method: "GET", pattern: at("/"), auth: false, handler: legal.home, limiter: "none" },
  { method: "GET", pattern: at("/logo\\.png"), auth: false, handler: async () => logo(), limiter: "none" },
  { method: "GET", pattern: at("/guide"), auth: false, handler: legal.guide, limiter: "none" },
  { method: "GET", pattern: at("/demo"), auth: false, handler: legal.demo, limiter: "none" },
  { method: "GET", pattern: at("/privacy"), auth: false, handler: legal.privacy, limiter: "none" },
  { method: "GET", pattern: at("/terms"), auth: false, handler: legal.terms, limiter: "none" },
  { method: "GET", pattern: at(`/export/${token}`), auth: false, handler: lists.downloadExport, limiter: "none" },
  { method: "GET", pattern: at(`/review/${token}`), auth: false, handler: review.reviewPage, limiter: "none" },
  { method: "POST", pattern: at(`/review/${token}`), auth: false, handler: review.reviewAction },
  { method: "GET", pattern: at(`/review/${token}/file`), auth: false, handler: review.reviewFile, limiter: "none" },
  { method: "POST", pattern: at("/v1/game/reports"), auth: false, handler: games.receiveGameReport, limiter: "none", skipIpLimit: true },

  { method: "GET", pattern: at("/v1/me"), auth: true, handler: me },
  { method: "GET", pattern: at("/v1/preferences"), auth: true, handler: preferences.getPreferences },
  { method: "PATCH", pattern: at("/v1/preferences"), auth: true, handler: preferences.patchPreferences },
  { method: "GET", pattern: at("/v1/sessions"), auth: true, handler: listSessions },
  { method: "DELETE", pattern: at("/v1/session"), auth: true, handler: endCurrentSession },
  { method: "DELETE", pattern: at(`/v1/sessions/${id}`), auth: true, handler: endSession },
  { method: "GET", pattern: at("/v1/users"), auth: true, handler: lookupUsers },
  { method: "GET", pattern: at("/v1/notifications"), auth: true, handler: listNotifications },
  { method: "POST", pattern: at("/v1/notifications/read"), auth: true, handler: readNotifications },
  { method: "GET", pattern: at("/v1/tasks/mine"), auth: true, handler: items.myTasks },
  { method: "GET", pattern: at("/v1/search"), auth: true, handler: items.search },
  { method: "GET", pattern: at("/v1/trash"), auth: true, handler: lists.trash },
  { method: "POST", pattern: at("/v1/trash/restore"), auth: true, handler: trashRoutes.restoreSelected },
  { method: "POST", pattern: at("/v1/trash/delete"), auth: true, handler: trashRoutes.deleteSelected },
  { method: "POST", pattern: at("/v1/trash/empty"), auth: true, handler: trashRoutes.emptyTrash },
  { method: "GET", pattern: at("/v1/templates"), auth: true, handler: lists.listTemplates },

  { method: "POST", pattern: at("/v1/uploads"), auth: true, handler: uploads.startUpload },
  { method: "PUT", pattern: at(`/v1/uploads/${id}/parts/${part}`), auth: true, handler: uploads.putPart },
  { method: "DELETE", pattern: at(`/v1/uploads/${id}`), auth: true, handler: uploads.cancelUpload },
  { method: "POST", pattern: at("/v1/submissions"), auth: true, handler: submissions.submit },

  { method: "GET", pattern: at("/v1/lists"), auth: true, handler: lists.home },
  { method: "POST", pattern: at("/v1/lists"), auth: true, handler: lists.createList },
  { method: "POST", pattern: at("/v1/lists/open"), auth: true, handler: lists.openByCode },
  { method: "POST", pattern: at("/v1/lists/import"), auth: true, handler: lists.importList },
  { method: "GET", pattern: at(`/v1/lists/${id}`), auth: true, handler: lists.getList },
  { method: "PATCH", pattern: at(`/v1/lists/${id}`), auth: true, handler: lists.updateList },
  { method: "DELETE", pattern: at(`/v1/lists/${id}`), auth: true, handler: lists.deleteList },
  { method: "GET", pattern: at(`/v1/lists/${id}/changes`), auth: true, handler: lists.listChanges },
  { method: "POST", pattern: at(`/v1/lists/${id}/restore`), auth: true, handler: lists.restoreList },
  { method: "POST", pattern: at(`/v1/lists/${id}/duplicate`), auth: true, handler: lists.duplicateList },
  { method: "POST", pattern: at(`/v1/lists/${id}/code`), auth: true, handler: lists.rotateCode },
  { method: "DELETE", pattern: at(`/v1/lists/${id}/visit`), auth: true, handler: lists.forgetVisit },
  { method: "POST", pattern: at(`/v1/lists/${id}/seen`), auth: true, handler: lists.markSeen },
  { method: "PUT", pattern: at(`/v1/lists/${id}/presence`), auth: true, handler: lists.putPresence },
  { method: "DELETE", pattern: at(`/v1/lists/${id}/presence`), auth: true, handler: lists.deletePresence },
  { method: "POST", pattern: at(`/v1/lists/${id}/export`), auth: true, handler: lists.createExport },
  { method: "POST", pattern: at(`/v1/lists/${id}/undo`), auth: true, handler: undoLast },
  { method: "GET", pattern: at(`/v1/lists/${id}/activity`), auth: true, handler: listActivity },
  { method: "GET", pattern: at(`/v1/lists/${id}/game-keys`), auth: true, handler: games.listGameKeys },
  { method: "POST", pattern: at(`/v1/lists/${id}/game-keys`), auth: true, handler: games.createGameKey },
  { method: "DELETE", pattern: at(`/v1/lists/${id}/game-keys/${id}`), auth: true, handler: games.deleteGameKey },
  { method: "GET", pattern: at(`/v1/lists/${id}/reports`), auth: true, handler: games.listReports },
  { method: "POST", pattern: at(`/v1/reports/${id}/approve`), auth: true, handler: games.approveReport },
  { method: "POST", pattern: at(`/v1/reports/${id}/dismiss`), auth: true, handler: games.dismissReport },

  { method: "POST", pattern: at(`/v1/lists/${id}/items`), auth: true, handler: items.addItem },
  { method: "PATCH", pattern: at(`/v1/items/${id}`), auth: true, handler: items.updateItem },
  { method: "DELETE", pattern: at(`/v1/items/${id}`), auth: true, handler: items.deleteItem },
  { method: "POST", pattern: at(`/v1/items/${id}/move`), auth: true, handler: items.moveItem },
  { method: "POST", pattern: at(`/v1/items/${id}/restore`), auth: true, handler: items.restoreItem },
  { method: "GET", pattern: at(`/v1/items/${id}/comments`), auth: true, handler: comments.listComments },
  { method: "POST", pattern: at(`/v1/items/${id}/comments`), auth: true, handler: comments.addComment },
  { method: "DELETE", pattern: at(`/v1/comments/${id}`), auth: true, handler: comments.deleteComment },

  { method: "PUT", pattern: at(`/v1/lists/${id}/members/${uid}`), auth: true, handler: sharing.putMember },
  { method: "DELETE", pattern: at(`/v1/lists/${id}/members/${uid}`), auth: true, handler: sharing.deleteMember },
  { method: "PUT", pattern: at(`/v1/lists/${id}/assignments/${uid}`), auth: true, handler: sharing.putAssignment },
  { method: "DELETE", pattern: at(`/v1/lists/${id}/assignments/${uid}`), auth: true, handler: sharing.deleteAssignment },
];

async function meta(_request: Request, env: Env): Promise<Response> {
  return json({
    latestPluginVersion: env.latestPluginVersion,
    minPluginVersion: env.minPluginVersion,
    paid: isPaid(env),
    storeUrl: storeUrl(env),
    environment: env.environmentName,
  });
}

function versionBelow(version: string, minimum: string): boolean {
  const a = version.split(".").map(Number);
  const b = minimum.split(".").map(Number);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0;
    const y = b[i] ?? 0;
    if (x !== y) return x < y;
  }
  return false;
}

async function dispatch(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const matches = routes.filter((r) => r.pattern.test(url.pathname));
  if (matches.length === 0) throw new ApiError("not_found", "Unknown endpoint.");
  const route = matches.find((r) => r.method === request.method);
  if (!route) throw new ApiError("bad_request", "Method not allowed for this endpoint.");
  const params = (route.pattern.exec(url.pathname) ?? []).slice(1);

  const pluginVersion = request.headers.get("x-plugin-version");
  if (pluginVersion && route.handler !== meta && versionBelow(pluginVersion, env.minPluginVersion)) {
    throw new ApiError("upgrade_required", "This version of CheckpointLTC is too old. Update it in Plugins, Manage Plugins, then reopen Studio.");
  }

  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  if (!route.skipIpLimit) await enforceRateLimit(env.ipLimiter, ip);

  if (!route.auth) {
    if (route.limiter === "poll") await enforceRateLimit(env.pollLimiter, ip);
    else if (route.limiter !== "none") await enforceRateLimit(env.authLimiter, ip);
    return (route.handler as Open)(request, env, ...params);
  }
  const caller = await authenticate(request, env);
  await enforceRateLimit(env.apiLimiter, String(caller.userId));
  return (route.handler as Authed)(request, env, caller, ...params);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (new URL(request.url).pathname.startsWith("/media/")) return await serveMedia(request, env);
      return await dispatch(request, env);
    } catch (err) {
      if (err instanceof ApiError) return errorResponse(err);
      console.error("unhandled", err instanceof Error ? err.stack : err);
      return errorResponse(new ApiError("internal", "Something went wrong on the server."));
    }
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await cleanup(env);
  },
} satisfies ExportedHandler<Env>;
