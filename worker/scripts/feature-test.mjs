import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.apiUrl ?? "http://127.0.0.1:8787";
const reviewPassword = process.env.reviewPassword ?? "testpass";
const ids = { owner: 1, editor: 156, admin: 261, viewer: 16, stranger: 18, helper: 2 };

let passed = 0;
let failed = 0;

function check(label, condition, detail) {
  if (condition) {
    passed++;
    console.log(`  ok    ${label}`);
  } else {
    failed++;
    console.log(`  FAIL  ${label}${detail !== undefined ? `  (${typeof detail === "string" ? detail : JSON.stringify(detail)})` : ""}`);
  }
}

async function call(user, method, path, body, extraHeaders = {}) {
  const headers = { "content-type": "application/json", "x-plugin-version": "1.0.0", ...extraHeaders };
  if (user) {
    headers.authorization = `Bearer ${user.key}`;
    headers["x-roblox-user-id"] = String(user.userId);
  }
  const res = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: res.status, data, headers: res.headers };
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

async function upload(user, name, bytes) {
  const start = await call(user, "POST", "/v1/uploads", { name, size: bytes.length });
  if (start.status !== 201) return start;
  const { uploadId, parts, chunkBytes } = start.data;
  for (let n = 0; n < parts; n++) {
    const chunk = bytes.subarray(n * chunkBytes, (n + 1) * chunkBytes);
    const res = await call(user, "PUT", `/v1/uploads/${uploadId}/parts/${n}`, { data: Buffer.from(chunk).toString("base64") });
    if (res.status !== 200) return res;
  }
  return { status: 201, data: { uploadId } };
}

const png = (marker = "") => {
  const head = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return Buffer.concat([head, Buffer.alloc(700_000, 7), Buffer.from(marker)]);
};

console.log(`Feature test against ${base}\n`);
const u = {};
for (const [name, id] of Object.entries(ids)) u[name] = await register(id);

console.log("Lists, templates and roles");
const templates = await call(u.owner, "GET", "/v1/templates");
check("templates listed", templates.status === 200 && templates.data.templates.some((t) => t.key === "launch"));
const launch = await call(u.owner, "POST", "/v1/lists", { template: "launch" });
check("template list created with tasks", launch.status === 201 && launch.data.items.length === 12, launch.data?.items?.length);
check("template tasks keep sections", launch.data.items[0].section === "Gameplay");
const listId = launch.data.list.id;
check("owner name comes from Roblox", launch.data.list.owner.name !== null, launch.data.list.owner);
check("admin added", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.admin}`, { role: "admin" })).status === 200);
check("editor added", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.editor}`, { role: "editor" })).status === 200);
check("admin adds a viewer", (await call(u.admin, "PUT", `/v1/lists/${listId}/members/${ids.viewer}`, { role: "viewer" })).status === 200);
check("admin cannot make admins (403)", (await call(u.admin, "PUT", `/v1/lists/${listId}/members/${ids.helper}`, { role: "admin" })).status === 403);
check("admin renames", (await call(u.admin, "PATCH", `/v1/lists/${listId}`, { title: "Launch plan" })).status === 200);
check("admin rotates code", (await call(u.admin, "POST", `/v1/lists/${listId}/code`)).status === 200);
check("admin cannot delete list (403)", (await call(u.admin, "DELETE", `/v1/lists/${listId}`)).status === 403);
check("admin cannot archive (403)", (await call(u.admin, "PATCH", `/v1/lists/${listId}`, { archived: true })).status === 403);
check("editor cannot manage people (403)", (await call(u.editor, "PUT", `/v1/lists/${listId}/members/${ids.helper}`, {})).status === 403);
check("admin can leave the list", (await call(u.admin, "DELETE", `/v1/lists/${listId}/members/${ids.admin}`)).status === 200);
check("owner re adds admin", (await call(u.owner, "PUT", `/v1/lists/${listId}/members/${ids.admin}`, { role: "admin" })).status === 200);

console.log("\nTasks");
const first = launch.data.items[0];
const second = launch.data.items[1];
const third = launch.data.items[2];
const edited = await call(u.editor, "PATCH", `/v1/items/${first.id}`, {
  priority: 3,
  dueAt: Date.now() + 86_400_000,
  label: "Bug",
  notes: "Check on mobile too",
  assigneeId: ids.editor,
  link: { kind: "script", path: "ServerScriptService.Main", line: 42 },
});
check("editor sets priority, due date, label, notes, assignee and link", edited.status === 200 && edited.data.item.priority === 3 && edited.data.item.link.line === 42, edited.data);
check("bad label refused", (await call(u.editor, "PATCH", `/v1/items/${first.id}`, { label: "Art" })).status === 400);
check("cannot assign someone not on the list", (await call(u.editor, "PATCH", `/v1/items/${first.id}`, { assigneeId: ids.stranger })).status === 400);
check("assign to viewer on the list", (await call(u.owner, "PATCH", `/v1/items/${second.id}`, { assigneeId: ids.viewer })).status === 200);
check("viewer checks own task", (await call(u.viewer, "PATCH", `/v1/items/${second.id}`, { done: true })).status === 200);
check("viewer cannot edit own task text (403)", (await call(u.viewer, "PATCH", `/v1/items/${second.id}`, { text: "x" })).status === 403);
check("viewer cannot check someone else's task (403)", (await call(u.viewer, "PATCH", `/v1/items/${third.id}`, { done: true })).status === 403);
const mine = await call(u.editor, "GET", "/v1/tasks/mine");
check("My tasks shows assigned task across lists", mine.status === 200 && mine.data.items.some((i) => i.id === first.id && i.listTitle === "Launch plan"));
const moved = await call(u.editor, "POST", `/v1/items/${third.id}/move`, { belowId: first.id });
check("drag to top", moved.status === 200 && moved.data.item.position < first.position, moved.data);
const between = await call(u.editor, "POST", `/v1/items/${third.id}/move`, { aboveId: first.id, belowId: second.id, section: "Polish" });
check("drag between two tasks into a section", between.status === 200 && between.data.item.position > first.position && between.data.item.section === "Polish");
const order = (await call(u.owner, "GET", `/v1/lists/${listId}`)).data.items.map((i) => i.id);
check("order stuck", order.indexOf(third.id) === order.indexOf(first.id) + 1, order.slice(0, 4));

console.log("\nSeveral people on one task");
const multi = await call(u.owner, "PATCH", `/v1/items/${third.id}`, { assigneeIds: [ids.editor, ids.viewer] });
check(
  "give a task to two people",
  multi.status === 200 && multi.data.item.assigneeIds.length === 2 && multi.data.item.assigneeId === ids.editor,
  multi.data,
);
check("second person sees it in My tasks", (await call(u.viewer, "GET", "/v1/tasks/mine")).data.items.some((i) => i.id === third.id));
check("second person can check it off", (await call(u.viewer, "PATCH", `/v1/items/${third.id}`, { done: true })).status === 200);
check("second person can comment", (await call(u.viewer, "POST", `/v1/items/${third.id}/comments`, { body: "on it" })).status === 201);
check("second person can uncheck it", (await call(u.viewer, "PATCH", `/v1/items/${third.id}`, { done: false })).status === 200);
check(
  "stranger cannot be one of them",
  (await call(u.owner, "PATCH", `/v1/items/${third.id}`, { assigneeIds: [ids.editor, ids.stranger] })).status === 400,
);
check(
  "more than 10 people refused",
  (await call(u.owner, "PATCH", `/v1/items/${third.id}`, { assigneeIds: Array.from({ length: 11 }, (_, n) => n + 100) })).status === 400,
);
const single = await call(u.owner, "PATCH", `/v1/items/${third.id}`, { assigneeId: ids.editor });
check("old assigneeId still works", single.status === 200 && single.data.item.assigneeIds.join() === String(ids.editor), single.data);
const undoAssign = await call(u.owner, "POST", `/v1/lists/${listId}/undo`);
check(
  "undo brings both people back",
  undoAssign.status === 200 && undoAssign.data.items.find((i) => i.id === third.id)?.assigneeIds.length === 2,
  undoAssign.data,
);
const cleared = await call(u.owner, "PATCH", `/v1/items/${third.id}`, { assigneeIds: [] });
check("clear everyone", cleared.status === 200 && cleared.data.item.assigneeIds.length === 0 && cleared.data.item.assigneeId === null);
check("unassigned viewer cannot check it now (403)", (await call(u.viewer, "PATCH", `/v1/items/${third.id}`, { done: true })).status === 403);

console.log("\nAuto assign");
check("editor cannot set auto assign (403)", (await call(u.editor, "PATCH", `/v1/lists/${listId}`, { autoAssignees: [ids.editor] })).status === 403);
check("stranger cannot be auto assigned", (await call(u.owner, "PATCH", `/v1/lists/${listId}`, { autoAssignees: [ids.stranger] })).status === 400);
const auto = await call(u.owner, "PATCH", `/v1/lists/${listId}`, { autoAssignees: [ids.editor] });
check("owner turns on auto assign", auto.status === 200 && auto.data.list.autoAssignees.join() === String(ids.editor), auto.data);
const autoItem = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Auto assigned task" });
check("new task gets auto assigned", autoItem.status === 201 && autoItem.data.item.assigneeIds.join() === String(ids.editor), autoItem.data);
const oldClient = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Old plugin task" });
check("works for old plugins too", oldClient.data.item.assigneeId === ids.editor);
const picked = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Nobody on this", assigneeIds: [] });
check("can still pick nobody", picked.status === 201 && picked.data.item.assigneeIds.length === 0);
check("viewers do not see auto assign", (await call(u.viewer, "GET", `/v1/lists/${listId}`)).data.list.autoAssignees.length === 0);
const autoOff = await call(u.owner, "PATCH", `/v1/lists/${listId}`, { autoAssignees: [] });
check("turn auto assign off", autoOff.status === 200 && autoOff.data.list.autoAssignees.length === 0);
const afterOff = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "After off" });
check("no one assigned after turning it off", afterOff.data.item.assigneeIds.length === 0);
for (const extra of [autoItem, oldClient, picked, afterOff]) await call(u.owner, "DELETE", `/v1/items/${extra.data.item.id}`);

console.log("\nSplit a task");
const long = await call(u.editor, "POST", `/v1/lists/${listId}/items`, {
  text: "Fix the shop and redo the lobby lighting",
  section: "Polish",
  priority: 2,
  assigneeIds: [ids.editor, ids.viewer],
});
const longId = long.data.item.id;
check("viewer cannot split (403)", (await call(u.viewer, "POST", `/v1/items/${longId}/split`, { parts: ["a", "b"] })).status === 403);
check("one part refused", (await call(u.editor, "POST", `/v1/items/${longId}/split`, { parts: ["only"] })).status === 400);
check(
  "too many parts refused",
  (await call(u.editor, "POST", `/v1/items/${longId}/split`, { parts: Array.from({ length: 11 }, (_, n) => `p${n}`) })).status === 400,
);
check(
  "stale version refused (409)",
  (await call(u.editor, "POST", `/v1/items/${longId}/split`, { parts: ["a", "b"], version: long.data.item.version + 5 })).status === 409,
);
const split = await call(u.editor, "POST", `/v1/items/${longId}/split`, {
  parts: ["Fix the shop", "Redo the lobby lighting", "Test both on mobile"],
  version: long.data.item.version,
});
const splitItems = split.data.items ?? [];
const original = splitItems.find((i) => i.id === longId);
const made = splitItems.filter((i) => i.text === "Redo the lobby lighting" || i.text === "Test both on mobile");
check("split into three", split.status === 200 && original?.text === "Fix the shop" && made.length === 2, split.data);
check("new parts stay in the same section", made.every((i) => i.section === "Polish"));
check("new parts keep priority and people", made.every((i) => i.priority === 2 && i.assigneeIds.length === 2));
const at = splitItems.findIndex((i) => i.id === longId);
check(
  "new parts sit right below the original",
  splitItems[at + 1]?.text === "Redo the lobby lighting" && splitItems[at + 2]?.text === "Test both on mobile",
  splitItems.map((i) => i.text),
);
const undoSplit = await call(u.editor, "POST", `/v1/lists/${listId}/undo`);
const afterUndo = undoSplit.data.items ?? [];
check(
  "undo puts the split back together",
  undoSplit.status === 200 &&
    afterUndo.find((i) => i.id === longId)?.text === "Fix the shop and redo the lobby lighting" &&
    !afterUndo.some((i) => i.text === "Redo the lobby lighting"),
  afterUndo.map((i) => i.text),
);
await call(u.editor, "DELETE", `/v1/items/${longId}`);

console.log("\nSearch");
const found = await call(u.viewer, "GET", `/v1/search?q=${encodeURIComponent("mobile")}`);
check("search finds text in tasks I can see", found.status === 200 && found.data.items.length >= 1);
check("stranger search finds nothing", (await call(u.stranger, "GET", "/v1/search?q=mobile")).data.items.length === 0);
check("filter by label", (await call(u.owner, "GET", "/v1/search?label=Bug")).data.items.every((i) => i.label === "Bug"));

console.log("\nComments and mentions");
const ownerName = launch.data.list.owner.name;
const comment = await call(u.editor, "POST", `/v1/items/${first.id}/comments`, { body: `@${ownerName} can you look at this` });
check("editor comments", comment.status === 201, comment.data);
check("mention resolved to owner", comment.data.comment?.mentions?.includes(ids.owner), comment.data);
const notes = await call(u.owner, "GET", "/v1/notifications");
check("owner notified of mention", notes.data.notifications.some((n) => n.kind === "comment.mention"));
check("editor got a task assigned notification? (self assign does not notify)", !(await call(u.editor, "GET", "/v1/notifications")).data.notifications.some((n) => n.kind === "task.assigned" && n.itemId === first.id));
check("viewer was notified of the task given to them", (await call(u.viewer, "GET", "/v1/notifications")).data.notifications.some((n) => n.kind === "task.assigned"));
check("viewer cannot comment on others' tasks (403)", (await call(u.viewer, "POST", `/v1/items/${first.id}/comments`, { body: "hi" })).status === 403);
check("viewer can comment on own task", (await call(u.viewer, "POST", `/v1/items/${second.id}/comments`, { body: "done!" })).status === 201);
check("comments listed", (await call(u.viewer, "GET", `/v1/items/${first.id}/comments`)).data.comments.length === 1);
check("comment count on task", (await call(u.owner, "GET", `/v1/lists/${listId}`)).data.items.find((i) => i.id === first.id).commentCount === 1);
check("mark notifications read", (await call(u.owner, "POST", "/v1/notifications/read", {})).status === 200);
check("unread is zero", (await call(u.owner, "GET", "/v1/notifications")).data.unread === 0);

console.log("\nDelta sync and seen");
const snapshot = await call(u.owner, "GET", `/v1/lists/${listId}`);
const rev = snapshot.data.revision;
check("seen marked", (await call(u.owner, "POST", `/v1/lists/${listId}/seen`, {})).status === 200);
check("no change gives mode none", (await call(u.owner, "GET", `/v1/lists/${listId}/changes?since=${rev}`)).data.mode === "none");
await call(u.editor, "PATCH", `/v1/items/${third.id}`, { done: true });
await call(u.editor, "POST", `/v1/lists/${listId}/items`, { text: "Fresh task" });
const delta = await call(u.owner, "GET", `/v1/lists/${listId}/changes?since=${rev}`);
check("delta returns only changed tasks", delta.data.mode === "delta" && delta.data.items.length === 2, delta.data);
check("delta says someone else changed it", delta.data.othersChanged === true, delta.data);
const ownRev = (await call(u.owner, "GET", `/v1/lists/${listId}`)).data.revision;
await call(u.owner, "PATCH", `/v1/items/${third.id}`, { done: false });
const own = await call(u.owner, "GET", `/v1/lists/${listId}/changes?since=${ownRev}`);
check("my own change is not someone else's", own.data.mode === "delta" && own.data.othersChanged === false, own.data);
await call(u.owner, "PATCH", `/v1/items/${third.id}`, { done: true });
const home = await call(u.owner, "GET", "/v1/lists");
const summary = home.data.mine.find((l) => l.id === listId);
check("home shows changes since I last looked", summary.unseen === 2, summary);
check("home counts come from stored columns", summary.itemCount === 13 && summary.doneCount === 2, summary);
await call(u.owner, "PATCH", `/v1/lists/${listId}`, { title: "Launch plan v2" });
check("a rename makes delta fall back to full", (await call(u.owner, "GET", `/v1/lists/${listId}/changes?since=${rev}`)).data.changed === true);

console.log("\nPresence");
check("editor says where they are", (await call(u.editor, "PUT", `/v1/lists/${listId}/presence`, { itemId: first.id, placeId: 1818 })).status === 200);
const presence = (await call(u.owner, "GET", `/v1/lists/${listId}`)).data.presence;
check("owner sees editor on that task", presence.some((p) => p.userId === ids.editor && p.itemId === first.id));

console.log("\nTrash, undo and archive");
const deleted = await call(u.editor, "DELETE", `/v1/items/${third.id}`);
check("delete goes to trash", deleted.status === 200 && deleted.data.restorableUntil > Date.now());
check("trash lists it", (await call(u.editor, "GET", "/v1/trash")).data.items.some((i) => i.id === third.id));
check("restore from trash", (await call(u.editor, "POST", `/v1/items/${third.id}/restore`)).status === 200);
await call(u.editor, "PATCH", `/v1/items/${third.id}`, { text: "Typo here" });
const undone = await call(u.editor, "POST", `/v1/lists/${listId}/undo`);
check("undo reverts my last edit", undone.status === 200 && undone.data.items.find((i) => i.id === third.id).text !== "Typo here", undone.data?.items?.find?.((i) => i.id === third.id));
const undoneAgain = await call(u.editor, "POST", `/v1/lists/${listId}/undo`);
check("undo again goes one step further back", undoneAgain.status === 200);
check("viewer cannot undo (403)", (await call(u.viewer, "POST", `/v1/lists/${listId}/undo`)).status === 403);
check("owner archives", (await call(u.owner, "PATCH", `/v1/lists/${listId}`, { archived: true })).status === 200);
check("archived list refuses edits (403)", (await call(u.editor, "POST", `/v1/lists/${listId}/items`, { text: "x" })).status === 403);
check("archived list is still readable", (await call(u.viewer, "GET", `/v1/lists/${listId}`)).status === 200);
check("owner unarchives", (await call(u.owner, "PATCH", `/v1/lists/${listId}`, { archived: false })).status === 200);
check("pin to a game", (await call(u.owner, "PATCH", `/v1/lists/${listId}`, { placeId: 1818 })).data.list.placeId === 1818);

console.log("\nDuplicate, export and import");
const copy = await call(u.viewer, "POST", `/v1/lists/${listId}/duplicate`, {});
check("viewer duplicates into their own list", copy.status === 201 && copy.data.role === "owner" && copy.data.items.length === 13, copy.data?.items?.length);
const exportLink = await call(u.owner, "POST", `/v1/lists/${listId}/export`, { format: "md" });
check("export link made", exportLink.status === 200 && exportLink.data.url.includes("/export/"));
const exportPath = new URL(exportLink.data.url).pathname;
const md = await fetch(base + exportPath);
const mdText = await md.text();
check("markdown export downloads", md.status === 200 && mdText.startsWith("# Launch plan v2") && mdText.includes("- ["), mdText.slice(0, 80));
const imported = await call(u.stranger, "POST", "/v1/lists/import", { format: "md", content: mdText });
check("markdown import round trips", imported.status === 201 && imported.data.items.length === 13 && imported.data.list.title === "Launch plan v2", imported.data?.items?.length);
check("imported labels kept", imported.data.items.some((i) => i.label === "Bug"));
check("export without a timezone writes UTC", / due \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC(\n| )/.test(mdText), mdText);
const tzLink = await call(u.owner, "POST", `/v1/lists/${listId}/export`, { format: "md", tz: [[0, -300]] });
const tzText = await (await fetch(base + new URL(tzLink.data.url).pathname)).text();
check("export with a timezone writes local time and the offset", / due \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC-05:00/.test(tzText), tzText);
const tzImport = await call(u.stranger, "POST", "/v1/lists/import", { format: "md", content: tzText });
const dueBefore = imported.data.items.filter((i) => i.dueAt).map((i) => i.dueAt);
const dueAfter = tzImport.data.items.filter((i) => i.dueAt).map((i) => i.dueAt);
check(
  "due dates survive import in either timezone",
  dueBefore.length > 0 && dueBefore.length === dueAfter.length && dueBefore.every((d, n) => d === dueAfter[n]) && !tzImport.data.items.some((i) => i.text.includes(" due ")),
  { dueBefore, dueAfter },
);
check("bad timezone falls back to UTC", (await call(u.owner, "POST", `/v1/lists/${listId}/export`, { format: "md", tz: [["x", 9999]] })).status === 200);
const jsonLink = await call(u.owner, "POST", `/v1/lists/${listId}/export`, { format: "json" });
const jsonText = await (await fetch(base + new URL(jsonLink.data.url).pathname)).text();
const jsonImport = await call(u.stranger, "POST", "/v1/lists/import", { format: "json", content: jsonText, title: "From JSON" });
check("json import works", jsonImport.status === 201 && jsonImport.data.items.length === 13);
check("bad json import refused", (await call(u.stranger, "POST", "/v1/lists/import", { format: "json", content: "{nope" })).status === 400);
check("expired export token refused", (await fetch(`${base}/export/${"a".repeat(43)}`)).status === 410);

console.log("\nPreferences");
check("defaults come back", (await call(u.owner, "GET", "/v1/preferences")).data.preferences.showHints === true);
check("save a preference", (await call(u.owner, "PATCH", "/v1/preferences", { compact: true, accent: "red" })).data.preferences.compact === true);
check("bad preference refused", (await call(u.owner, "PATCH", "/v1/preferences", { refreshSeconds: 1 })).status === 400);
check("unknown preference refused", (await call(u.owner, "PATCH", "/v1/preferences", { hacker: true })).status === 400);

console.log("\nBug reports, feedback and attachments");
check("attach blocked before I understand", (await call(u.owner, "POST", "/v1/uploads", { name: "shot.png", size: 100 })).status === 403);
await call(u.owner, "PATCH", "/v1/preferences", { uploadWarningAccepted: true });
check("wrong file type refused", (await call(u.owner, "POST", "/v1/uploads", { name: "virus.exe", size: 100 })).status === 400);
const tooBig = await call(u.owner, "POST", "/v1/uploads", { name: "big.mp4", size: 11 * 1024 * 1024 });
check("too big file refused with a clear message", tooBig.status === 413 && tooBig.data.error.message.includes("10.0 MB"), tooBig.data);
const fake = await upload(u.owner, "fake.png", Buffer.alloc(2000, 1));
const fakeSend = await call(u.owner, "POST", "/v1/submissions", { kind: "bug", title: "Fake", body: "x", uploadId: fake.data.uploadId });
check("fake png caught by header check", fakeSend.status === 400 && fakeSend.data.error.message.includes("not a real png"), fakeSend.data);
const clean = await upload(u.owner, "shot.png", png());
check("chunked upload", clean.status === 201, clean.data);
const bug = await call(u.owner, "POST", "/v1/submissions", {
  kind: "bug",
  title: "List does not refresh",
  body: "Added a task on one PC, the other did not update.",
  steps: "1. Open two Studios\n2. Add a task",
  includeInfo: true,
  studioInfo: "Windows, dark theme",
  uploadId: clean.data.uploadId,
});
check("bug report with clean image sent", bug.status === 201 && bug.data.attachment === "clean", bug.data);
const second2 = await call(u.owner, "POST", "/v1/submissions", { kind: "bug", title: "Again", body: "x" });
check("second bug in the hour blocked with countdown", second2.status === 429 && second2.data.error.retryAfterMs > 3_500_000, second2.data);
const feedback = await call(u.owner, "POST", "/v1/submissions", { kind: "feedback", title: "Dark mode", body: "More contrast", category: "UI" });
check("feedback still allowed in the same hour", feedback.status === 201, feedback.data);
const me = await call(u.owner, "GET", "/v1/me");
check("me shows both cooldowns", me.data.cooldowns.bugAvailableAt > Date.now() && me.data.cooldowns.feedbackAvailableAt > Date.now());
check("me shows attachment limits", me.data.limits.attachmentMaxBytes === 10 * 1024 * 1024 && me.data.limits.attachmentTypes.includes("mov"));

await call(u.editor, "PATCH", "/v1/preferences", { uploadWarningAccepted: true });
const flagged = await upload(u.editor, "bad.png", png("FLAGME"));
const held = await call(u.editor, "POST", "/v1/submissions", { kind: "bug", title: "Look at this", body: "x", uploadId: flagged.data.uploadId });
check("flagged attachment held, report still sent", held.status === 201 && held.data.attachment === "held" && held.data.reviewUrl, held.data);
const reviewPath = new URL(held.data.reviewUrl).pathname;
const reviewPage = await fetch(base + reviewPath);
check("private review page opens", reviewPage.status === 200 && (await reviewPage.text()).includes("Attachment held for review"));
check("review file served", (await fetch(`${base}${reviewPath}/file`)).status === 200);
const wrongPass = await fetch(base + reviewPath, { method: "POST", body: new URLSearchParams({ password: "nope", action: "approve" }) });
check("wrong review password refused", wrongPass.status === 403);
const strike = await fetch(base + reviewPath, { method: "POST", body: new URLSearchParams({ password: reviewPassword, action: "strike" }) });
check("reject with strike", strike.status === 200, await strike.text());
check("file gone after reject", (await fetch(`${base}${reviewPath}/file`)).status === 404);
const editorMe = await call(u.editor, "GET", "/v1/me");
check("strike means upload ban, plugin still works", editorMe.status === 200 && editorMe.data.uploads === "blocked");
check("upload banned account cannot attach", (await call(u.editor, "POST", "/v1/uploads", { name: "a.png", size: 10 })).data.error.code === "uploads_blocked");

await call(u.admin, "PATCH", "/v1/preferences", { uploadWarningAccepted: true });
const approveMe = await upload(u.admin, "ok.png", png("FLAGME"));
const heldTwo = await call(u.admin, "POST", "/v1/submissions", { kind: "feedback", title: "Idea", body: "x", uploadId: approveMe.data.uploadId });
const approvePath = new URL(heldTwo.data.reviewUrl).pathname;
const approve = await fetch(base + approvePath, { method: "POST", body: new URLSearchParams({ password: reviewPassword, action: "approve" }) });
check("approve a held attachment", approve.status === 200);
check("approved review link is done", (await fetch(base + approvePath)).status === 404);
check("approve does not ban", (await call(u.admin, "GET", "/v1/me")).data.uploads === "allowed");

await call(u.helper, "PATCH", "/v1/preferences", { uploadWarningAccepted: true });
const severeFile = await upload(u.helper, "worse.png", png("FLAGME"));
const heldThree = await call(u.helper, "POST", "/v1/submissions", { kind: "bug", title: "x", body: "x", uploadId: severeFile.data.uploadId });
const severePath = new URL(heldThree.data.reviewUrl).pathname;
await fetch(base + severePath, { method: "POST", body: new URLSearchParams({ password: reviewPassword, action: "illegal" }) });
const bannedCall = await call(u.helper, "GET", "/v1/lists");
check("illegal content means full ban", bannedCall.status === 403 && bannedCall.data.error.code === "banned");
check("evidence kept, review page still shows it", (await fetch(base + severePath)).status === 200);
ban("lift", ids.helper);

console.log("\nIn game bug reports");
const gameKey = await call(u.owner, "POST", `/v1/lists/${listId}/game-keys`, { label: "My obby" });
check("game key made once", gameKey.status === 201 && gameKey.data.key.startsWith("ltcg_"));
check("editor cannot make game keys (403)", (await call(u.editor, "POST", `/v1/lists/${listId}/game-keys`, {})).status === 403);
const report = (body) => call(null, "POST", "/v1/game/reports", body, { "x-checkpoint-key": gameKey.data.key });
check("wrong key refused", (await call(null, "POST", "/v1/game/reports", { kind: "bug" }, { "x-checkpoint-key": "ltcg_nope" })).status === 401);
check("unfiltered text refused", (await report({ kind: "bug", text: "Fell through map", playerId: 1, playerName: "Roblox" })).status === 400);
const sent = await report({ kind: "bug", text: "Fell through the map near spawn", playerId: 1, playerName: "Roblox", placeId: 1818, filtered: true });
check("player report received", sent.status === 201, sent.data);
check("same player again within a minute blocked", (await report({ kind: "bug", text: "Again", playerId: 1, filtered: true })).status === 429);
const inbox = await call(u.editor, "GET", `/v1/lists/${listId}/reports`);
check("report shows in the Inbox", inbox.data.reports.length === 1 && inbox.data.reports[0].playerName === "Roblox");
const approved = await call(u.editor, "POST", `/v1/reports/${inbox.data.reports[0].id}/approve`);
check("approve report into a task", approved.status === 200);
const afterApprove = (await call(u.owner, "GET", `/v1/lists/${listId}`)).data.items.find((i) => i.id === approved.data.itemId);
check("task has Bug label and Inbox section", afterApprove?.label === "Bug" && afterApprove?.section === "Inbox");
const unsaved = await report({ kind: "feedback", text: "From an unsaved place", playerId: 3, playerName: "Tester", placeId: 0, filtered: true });
check("report from an unsaved place (placeId 0) received", unsaved.status === 201, unsaved.data);
check("dismiss a report", (await call(u.editor, "POST", `/v1/reports/${unsaved.data.id}/dismiss`)).status === 200);
check("viewer cannot see inbox (403)", (await call(u.viewer, "GET", `/v1/lists/${listId}/reports`)).status === 403);
const other = await report({ kind: "feedback", text: "Second player", playerId: 4, playerName: "Other", filtered: true });
check("another player still gets through", other.status === 201, other.data);
let flood;
for (let i = 0; i < 12 && flood?.status !== 401; i++) flood = await report({ kind: "bug", text: `Spam ${i}`, playerId: 77, filtered: true });
check("one player flooding turns the key off (401)", flood.status === 401 && flood.data?.error?.revoked === true, flood.data);
check("turned off key refuses everyone", (await report({ kind: "feedback", text: "Hi", playerId: 5, filtered: true })).status === 401);
const keysAfter = (await call(u.owner, "GET", `/v1/lists/${listId}/game-keys`)).data.keys;
check("plugin sees the key as turned off", keysAfter.some((k) => k.revokedAt && k.revokedReason === "flood"));
const ownerNotes = (await call(u.owner, "GET", "/v1/notifications")).data.notifications;
check("owner gets a notification", ownerNotes.some((n) => n.kind === "gamekey.revoked"));
const revokedNote = ownerNotes.find((n) => n.kind === "gamekey.revoked");
const otherUnread = ownerNotes.filter((n) => !n.read && n.id !== revokedNote.id).length;
check("mark one notification read by id", (await call(u.owner, "POST", "/v1/notifications/read", { ids: [revokedNote.id] })).status === 200);
const afterRead = (await call(u.owner, "GET", "/v1/notifications")).data;
check(
  "only that one went read",
  afterRead.notifications.find((n) => n.id === revokedNote.id).read === true && afterRead.unread === otherUnread,
  { unread: afterRead.unread, otherUnread },
);
const strangerDelete = await call(u.stranger, "POST", "/v1/notifications/delete", { ids: [revokedNote.id] });
check("someone else cannot delete my notification", strangerDelete.data.deleted === 0);
check("delete a fixed alert", (await call(u.owner, "POST", "/v1/notifications/delete", { ids: [revokedNote.id] })).data.deleted === 1);
check("it's gone from notifications", !(await call(u.owner, "GET", "/v1/notifications")).data.notifications.some((n) => n.id === revokedNote.id));
check("it's in the trash", (await call(u.owner, "GET", "/v1/trash")).data.notifications.some((n) => n.id === revokedNote.id));
check("not in anyone else's trash", !(await call(u.stranger, "GET", "/v1/trash")).data.notifications.some((n) => n.id === revokedNote.id));
check("stranger cannot restore it", (await call(u.stranger, "POST", "/v1/trash/restore", { notifications: [revokedNote.id] })).data.restored === 0);
check("restore it (undo)", (await call(u.owner, "POST", "/v1/trash/restore", { notifications: [revokedNote.id] })).data.restored === 1);
check("it's back", (await call(u.owner, "GET", "/v1/notifications")).data.notifications.some((n) => n.id === revokedNote.id));
await call(u.owner, "POST", "/v1/notifications/delete", { ids: [revokedNote.id] });
check("delete forever from the trash", (await call(u.owner, "POST", "/v1/trash/delete", { notifications: [revokedNote.id] })).data.deleted === 1);
check("gone from the trash too", !(await call(u.owner, "GET", "/v1/trash")).data.notifications.some((n) => n.id === revokedNote.id));
const fresh = await call(u.owner, "POST", `/v1/lists/${listId}/game-keys`, { label: "Rotated" });
check("can make a new key after one is turned off", fresh.status === 201);

console.log("\nTrash for lists");
check("owner deletes list into trash", (await call(u.owner, "DELETE", `/v1/lists/${listId}`)).status === 200);
check("collaborators lose it", (await call(u.editor, "GET", `/v1/lists/${listId}`)).status === 404);
check("owner sees it in trash", (await call(u.owner, "GET", "/v1/trash")).data.lists.some((l) => l.id === listId));
check("editor cannot restore (404)", (await call(u.editor, "POST", `/v1/lists/${listId}/restore`)).status === 404);
check("owner restores", (await call(u.owner, "POST", `/v1/lists/${listId}/restore`)).status === 200);
check("collaborators get it back", (await call(u.editor, "GET", `/v1/lists/${listId}`)).status === 200);

console.log("\nRecycle bin");
const doomed = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Delete me forever" });
const keep = await call(u.owner, "POST", `/v1/lists/${listId}/items`, { text: "Bring me back" });
await call(u.owner, "DELETE", `/v1/items/${doomed.data.item.id}`);
await call(u.owner, "DELETE", `/v1/items/${keep.data.item.id}`);
check("stranger cannot erase others' trash", (await call(u.stranger, "POST", "/v1/trash/delete", { items: [doomed.data.item.id] })).data.skipped.length === 1);
const bulkRestore = await call(u.owner, "POST", "/v1/trash/restore", { items: [keep.data.item.id] });
check("restore selected", bulkRestore.status === 200 && bulkRestore.data.restored === 1);
const bulkDelete = await call(u.owner, "POST", "/v1/trash/delete", { items: [doomed.data.item.id] });
check("delete selected forever", bulkDelete.status === 200 && bulkDelete.data.deleted === 1);
check("erased task is gone from trash", !(await call(u.owner, "GET", "/v1/trash")).data.items.some((i) => i.id === doomed.data.item.id));
const spare = await call(u.owner, "POST", "/v1/lists", { title: "Spare" });
await call(u.owner, "DELETE", `/v1/lists/${spare.data.list.id}`);
const emptied = await call(u.owner, "POST", "/v1/trash/empty");
check("empty trash erases everything there", emptied.status === 200 && (await call(u.owner, "GET", "/v1/trash")).data.lists.length === 0);

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
