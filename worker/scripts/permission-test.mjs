import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.apiUrl ?? "http://127.0.0.1:8787";
const ids = { owner: 1, editor: 156, assignee: 261, viewer: 16, stranger: 18 };

let passed = 0;
let failed = 0;

function check(label, condition, detail) {
  if (condition) {
    passed++;
    console.log(`  ok    ${label}`);
  } else {
    failed++;
    console.log(`  FAIL  ${label}${detail ? `  (${detail})` : ""}`);
  }
}

async function call(user, method, path, body) {
  const headers = { "content-type": "application/json", "x-plugin-version": "1.0.0" };
  if (user) {
    headers.authorization = `Bearer ${user.key}`;
    headers["x-roblox-user-id"] = String(user.userId);
  }
  const res = await fetch(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  let data = null;
  try {
    data = await res.json();
  } catch {}
  return { status: res.status, data };
}

function ban(...args) {
  const script = fileURLToPath(new URL("./ban.mjs", import.meta.url));
  const result = spawnSync("node", [script, "--local", ...args.map(String)], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`ban ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
}

async function register(userId) {
  const res = await call(null, "POST", "/v1/register", { userId });
  if (res.status !== 201) throw new Error(`register ${userId} failed: ${res.status} ${JSON.stringify(res.data)}`);
  return { userId, key: res.data.key };
}

console.log(`Testing ${base}\n`);

const u = {};
for (const [name, id] of Object.entries(ids)) u[name] = await register(id);

console.log("Accounts");
check("second register of same UserId is refused", (await call(null, "POST", "/v1/register", { userId: ids.owner })).status === 409);
check("missing key is 401", (await call(null, "GET", "/v1/lists")).status === 401);
check("bad key is 401", (await call({ userId: ids.owner, key: "ltc_nope" }, "GET", "/v1/lists")).status === 401);
check(
  "owner key with editor UserId is 401",
  (await call({ userId: ids.editor, key: u.owner.key }, "GET", "/v1/lists")).status === 401,
);
check("non existent UserId cannot register", (await call(null, "POST", "/v1/register", { userId: 9999999999999 })).status === 400);

console.log("\nOwner creates a list");
const created = await call(u.owner, "POST", "/v1/lists", { title: "Map polish pass" });
check("create list is 201", created.status === 201, created.status);
const listId = created.data.list.id;
const code = created.data.list.shareCode;
check("owner sees share code", typeof code === "string" && code.length === 8);
const first = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Fix lighting in spawn room" });
check("owner adds item", first.status === 201);
const itemId = first.data.item.id;

console.log("\nStranger with nothing");
check("stranger cannot view (404)", (await call(u.stranger, "GET", `/v1/lists/${listId}`)).status === 404);
check("stranger cannot add (404)", (await call(u.stranger, "POST", `/v1/lists/${listId}/items`, { text: "x" })).status === 404);
check("stranger cannot edit item (404)", (await call(u.stranger, "PATCH", `/v1/items/${itemId}`, { done: true })).status === 404);
check("stranger cannot delete item (404)", (await call(u.stranger, "DELETE", `/v1/items/${itemId}`)).status === 404);
{
  const theirs = await call(u.stranger, "PATCH", `/v1/items/${itemId}`, { done: true });
  const missing = await call(u.stranger, "PATCH", "/v1/items/zzzzzzzzzzzzzz", { done: true });
  check(
    "stranger can't tell a hidden item from a missing one",
    theirs.status === missing.status && JSON.stringify(theirs.data) === JSON.stringify(missing.data),
    `${theirs.status} ${JSON.stringify(theirs.data)} vs ${missing.status} ${JSON.stringify(missing.data)}`,
  );
  const after = await call(u.owner, "GET", `/v1/lists/${listId}`);
  check("stranger's write attempts changed nothing (owner still sees the 1 item, unchecked)", after.data.items.length === 1 && after.data.items[0].done === false);
}

console.log("\nOwner grants editor and assignment");
check("owner adds editor", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.editor}`, { role: "editor" })).status === 200);
check("owner assigns list", (await call(u.owner, "PUT", `/v1/lists/${listId}/assignments/${ids.assignee}`)).status === 200);
check("owner cannot add self", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.owner}`, {})).status === 400);
check("bogus role refused", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.editor}`, { role: "owner" })).status === 400);

console.log("\nEditor");
const editorHome = await call(u.editor, "GET", "/v1/lists");
check("list shows in editor My lists", editorHome.data.mine.some((l) => l.id === listId && l.role === "editor"));
const added = await call(u.editor, "POST", `/v1/lists/${listId}/items`, { text: "Playtest round timer" });
check("editor adds item", added.status === 201);
check("editor checks item", (await call(u.editor, "PATCH", `/v1/items/${itemId}`, { done: true })).status === 200);
check("editor deletes own item", (await call(u.editor, "DELETE", `/v1/items/${added.data.item.id}`)).status === 200);
check("editor cannot rename (403)", (await call(u.editor, "PATCH", `/v1/lists/${listId}`, { title: "x" })).status === 403);
check("editor cannot add members (403)", (await call(u.editor, "PUT", `/v1/lists/${listId}/members/${ids.viewer}`, {})).status === 403);
check("editor cannot assign (403)", (await call(u.editor, "PUT", `/v1/lists/${listId}/assignments/${ids.viewer}`)).status === 403);
check("editor cannot rotate code (403)", (await call(u.editor, "POST", `/v1/lists/${listId}/code`)).status === 403);
check("editor cannot delete list (403)", (await call(u.editor, "DELETE", `/v1/lists/${listId}`)).status === 403);

console.log("\nAssigned user");
const assigneeHome = await call(u.assignee, "GET", "/v1/lists");
check("list shows in Assigned to me", assigneeHome.data.assigned.some((l) => l.id === listId));
const assigneeView = await call(u.assignee, "GET", `/v1/lists/${listId}`);
check("assignee can view", assigneeView.status === 200 && assigneeView.data.role === "viewer");
check("assignee does not get share code", assigneeView.data.list.shareCode === null);
check("assignee does not see member list", assigneeView.data.members.length === 0);
check("assignee cannot add (403)", (await call(u.assignee, "POST", `/v1/lists/${listId}/items`, { text: "x" })).status === 403);
check("assignee cannot check (403)", (await call(u.assignee, "PATCH", `/v1/items/${itemId}`, { done: false })).status === 403);

console.log("\nViewer by code");
check("viewer cannot view before code (404)", (await call(u.viewer, "GET", `/v1/lists/${listId}`)).status === 404);
check("wrong code is 404", (await call(u.viewer, "POST", "/v1/lists/open", { code: "ZZZZZZZZ" })).status === 404);
const opened = await call(u.viewer, "POST", "/v1/lists/open", { code: code.toLowerCase().replace(/(.{4})/, "$1 ") });
check("open by code (lowercase, spaced) works", opened.status === 200 && opened.data.role === "viewer");
check("list shows in Opened by code", (await call(u.viewer, "GET", "/v1/lists")).data.opened.some((l) => l.id === listId));
check("viewer cannot add (403)", (await call(u.viewer, "POST", `/v1/lists/${listId}/items`, { text: "x" })).status === 403);
check("viewer cannot delete item (403)", (await call(u.viewer, "DELETE", `/v1/items/${itemId}`)).status === 403);

console.log("\nTwo people editing at once");
const current = await call(u.owner, "GET", `/v1/lists/${listId}`);
const version = current.data.items.find((i) => i.id === itemId).version;
const rev = current.data.revision;
check("unchanged revision returns changed false", (await call(u.viewer, "GET", `/v1/lists/${listId}?rev=${rev}`)).data.changed === false);
const [a, b] = await Promise.all([
  call(u.owner, "PATCH", `/v1/items/${itemId}`, { text: "Owner wording", version }),
  call(u.editor, "PATCH", `/v1/items/${itemId}`, { text: "Editor wording", version }),
]);
const statuses = [a.status, b.status].sort();
check("one edit wins, the other gets 409", statuses[0] === 200 && statuses[1] === 409, statuses.join(","));
const loser = a.status === 409 ? a : b;
check("409 returns the current item", typeof loser.data?.item?.text === "string");
check("revision moved after edit", (await call(u.viewer, "GET", `/v1/lists/${listId}?rev=${rev}`)).data.changed === true);

console.log("\nMe and limits");
const meRes = await call(u.owner, "GET", "/v1/me");
check(
  "me returns the caps from the server",
  meRes.status === 200 && meRes.data.limits.itemsPerList === 500 && meRes.data.limits.itemMaxLength === 240,
);
check("me counts owned lists and items", meRes.data.usage.listsOwned === 1 && meRes.data.usage.lists[0].items >= 1);
check("me shows one editor", meRes.data.usage.lists[0].editors === 1);
check("me says uploads allowed", meRes.data.uploads === "allowed");
check("me needs a login (401)", (await call(null, "GET", "/v1/me")).status === 401);

console.log("\nActivity log");
const ownerLog = await call(u.owner, "GET", `/v1/lists/${listId}/activity`);
const kinds = ownerLog.data?.events?.map((e) => e.kind) ?? [];
check(
  "owner sees every change",
  ownerLog.status === 200 &&
    ["list.created", "item.added", "member.added", "assignment.added", "item.checked", "item.edited", "item.deleted"].every((k) =>
      kinds.includes(k),
    ),
  kinds.join(","),
);
check("events say who did it", ownerLog.data.events.some((e) => e.kind === "item.checked" && e.actorId === ids.editor));
check("the losing edit was not logged", kinds.filter((k) => k === "item.edited").length === 1);
check("newest event first", ownerLog.data.events[0].id > ownerLog.data.events.at(-1).id);
check("editor sees activity", (await call(u.editor, "GET", `/v1/lists/${listId}/activity`)).status === 200);
check("viewer cannot see activity (403)", (await call(u.viewer, "GET", `/v1/lists/${listId}/activity`)).status === 403);
check("stranger cannot see activity (404)", (await call(u.stranger, "GET", `/v1/lists/${listId}/activity`)).status === 404);
check(
  "after returns only newer events",
  (await call(u.owner, "GET", `/v1/lists/${listId}/activity?after=${ownerLog.data.events[0].id}`)).data.events.length === 0,
);

console.log("\nOwner revokes");
check("rotate code", (await call(u.owner, "POST", `/v1/lists/${listId}/code`)).status === 200);
check("viewer by old code loses access (404)", (await call(u.viewer, "GET", `/v1/lists/${listId}`)).status === 404);
check("remove editor", (await call(u.owner, "DELETE", `/v1/lists/${listId}/members/${ids.editor}`)).status === 200);
check("removed editor loses access (404)", (await call(u.editor, "POST", `/v1/lists/${listId}/items`, { text: "x" })).status === 404);
check("assignee dismisses own assignment", (await call(u.assignee, "DELETE", `/v1/lists/${listId}/assignments/${ids.assignee}`)).status === 200);
check("dismissed assignee loses access (404)", (await call(u.assignee, "GET", `/v1/lists/${listId}`)).status === 404);

{
  const kinds = (await call(u.owner, "GET", `/v1/lists/${listId}/activity`)).data.events.map((e) => e.kind);
  check("rotate and removals are logged", ["code.rotated", "member.removed", "assignment.removed"].every((k) => kinds.includes(k)));
}

console.log("\nValidation");
check("empty item refused", (await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "   " })).status === 400);
check("long item refused", (await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "a".repeat(241) })).status === 400);
check("non JSON body refused", (await fetch(`${base}/v1/register`, { method: "POST", body: "{nope" })).status === 400);
check("old plugin version refused (426)", (await fetch(`${base}/v1/lists`, { headers: { "x-plugin-version": "0.9.0" } })).status === 426);

console.log("\nDevices");
const devices = await call(u.owner, "GET", "/v1/sessions");
check(
  "owner has one device, marked current",
  devices.status === 200 && devices.data.sessions.length === 1 && devices.data.sessions[0].current === true,
);
check(
  "nobody can sign out someone else's device (404)",
  (await call(u.stranger, "DELETE", `/v1/sessions/${devices.data.sessions[0].id}`)).status === 404,
);
check("owner still signed in after that", (await call(u.owner, "GET", "/v1/lists")).status === 200);

console.log("\nBans");
const bannedList = await call(u.viewer, "POST", "/v1/lists", { title: "Banned owner list" });
const bannedListId = bannedList.data.list.id;
await call(u.viewer, "POST", `/v1/lists/${bannedListId}/items`, { text: "Still here" });
check(
  "owner adds a collaborator",
  (await call(u.viewer, "PUT", `/v1/lists/${bannedListId}/members/${ids.stranger}`, { role: "editor" })).status === 200,
);
ban("set", ids.viewer, "upload", "permission test upload strike");
const uploadBanned = await call(u.viewer, "GET", "/v1/me");
check("upload ban keeps the plugin working", uploadBanned.status === 200);
check("upload ban blocks uploads", uploadBanned.data.uploads === "blocked");
ban("set", ids.viewer, "full", "permission test full ban");
const fullBanned = await call(u.viewer, "GET", "/v1/lists");
check(
  "full ban is refused with the Terms of Service message",
  fullBanned.status === 403 && fullBanned.data.error.code === "banned" && fullBanned.data.error.message.includes("Terms of Service"),
  JSON.stringify(fullBanned.data),
);
check("full ban blocks every route", (await call(u.viewer, "GET", "/v1/me")).status !== 200);
check("collaborator still opens the banned owner's list", (await call(u.stranger, "GET", `/v1/lists/${bannedListId}`)).status === 200);
check(
  "collaborator can still add to it",
  (await call(u.stranger, "POST", `/v1/lists/${bannedListId}/items`, { text: "Carrying on" })).status === 201,
);
ban("lift", ids.viewer);
check("lifting keeps the old key dead, they log in again (401)", (await call(u.viewer, "GET", "/v1/lists")).status === 401);

console.log("\nSign out");
check("sign out this device", (await call(u.stranger, "DELETE", "/v1/session")).status === 200);
check("signed out key stops working (401)", (await call(u.stranger, "GET", "/v1/lists")).status === 401);

console.log("\nDelete");
check("owner deletes list", (await call(u.owner, "DELETE", `/v1/lists/${listId}`)).status === 200);
check("deleted list is gone (404)", (await call(u.owner, "GET", `/v1/lists/${listId}`)).status === 404);

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
