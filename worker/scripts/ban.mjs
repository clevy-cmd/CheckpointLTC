import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const levels = ["upload", "full", "illegal"];
const usage = `Usage:
  npm run ban -- show <userId>
  npm run ban -- set <userId> <upload|full|illegal> <reason>
  npm run ban -- lift <userId>
Add --local to change the local test database instead of the live one.`;

const args = process.argv.slice(2);
const local = args.includes("--local");
const [command, rawUserId, ...rest] = args.filter((a) => a !== "--local");

function stop(message) {
  console.error(message);
  process.exit(1);
}

if (!/^\d{1,19}$/.test(rawUserId ?? "") || !Number.isSafeInteger(Number(rawUserId))) stop(usage);
const userId = Number(rawUserId);
const quote = (text) => `'${String(text).replace(/'/g, "''")}'`;

function run(sql) {
  const folder = mkdtempSync(join(tmpdir(), "checkpointltc-ban-"));
  const file = join(folder, "ban.sql");
  writeFileSync(file, sql);
  try {
    const result = spawnSync(
      "npx",
      [
        "wrangler",
        "d1",
        "execute",
        "checkpointltc",
        local ? "--local" : "--remote",
        ...(local && process.env.persistTo ? ["--persist-to", `"${process.env.persistTo}"`] : []),
        "--json",
        "--file",
        `"${file}"`,
      ],
      { encoding: "utf8", shell: true },
    );
    if (result.status !== 0) stop(result.stderr || result.stdout);
    return JSON.parse(result.stdout);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

const now = Date.now();
const showSql = `SELECT level, reason, created_at, lifted_at FROM bans WHERE user_id = ${userId} ORDER BY id DESC LIMIT 10;`;

if (command === "show") {
  const rows = run(showSql).at(-1)?.results ?? [];
  if (rows.length === 0) console.log(`${userId} has never been banned.`);
  for (const r of rows) {
    const state = r.lifted_at ? `lifted ${new Date(r.lifted_at).toISOString()}` : "ACTIVE";
    console.log(`${r.level.padEnd(8)} ${new Date(r.created_at).toISOString()}  ${state}  ${r.reason}`);
  }
} else if (command === "set") {
  const [level, ...reasonWords] = rest;
  const reason = reasonWords.join(" ").trim();
  if (!levels.includes(level) || !reason) stop(usage);
  const endSessions =
    level === "upload" ? "" : `UPDATE users SET key_hash = ${quote(`revoked:${randomUUID()}`)} WHERE user_id = ${userId};`;
  run(`UPDATE bans SET lifted_at = ${now} WHERE user_id = ${userId} AND lifted_at IS NULL;
INSERT INTO bans (user_id, level, reason, created_at) VALUES (${userId}, ${quote(level)}, ${quote(reason)}, ${now});
${endSessions}`);
  console.log(`${userId} now has a ${level} ban.`);
  if (level === "illegal") console.log("Keep any evidence. Report CSAM to NCMEC: https://report.cybertip.org");
} else if (command === "lift") {
  run(`UPDATE bans SET lifted_at = ${now} WHERE user_id = ${userId} AND lifted_at IS NULL;`);
  console.log(`Lifted any active ban on ${userId}. They log in with Roblox again to get back in.`);
} else {
  stop(usage);
}
