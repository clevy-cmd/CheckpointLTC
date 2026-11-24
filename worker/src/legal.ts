import type { Env } from "./env";
import { headers, legalPage } from "./pages";

const discord = "https://discord.gg/5njkCsBdNd";
const updated = "November 24, 2026";

export async function home(request: Request, env: Env): Promise<Response> {
  const file = await env.ASSETS.fetch(new Request(new URL("/site/home.html", request.url)));
  if (!file.ok) return new Response("Not found", { status: 404 });
  return new Response(file.body, { headers: headers() });
}

export async function guide(request: Request, env: Env): Promise<Response> {
  const file = await env.ASSETS.fetch(new Request(new URL("/site/guide.html", request.url)));
  if (!file.ok) return new Response("Not found", { status: 404 });
  return new Response(file.body, { headers: headers() });
}

export async function demo(request: Request, env: Env): Promise<Response> {
  const file = await env.ASSETS.fetch(new Request(new URL("/site/video.html", request.url)));
  if (!file.ok) return new Response("Not found", { status: 404 });
  return new Response(file.body, { headers: headers() });
}

export async function privacy(): Promise<Response> {
  return legalPage(
    "Privacy policy",
    `Last updated ${updated}. CheckpointLTC is a Roblox Studio plugin I make and run through LTCLevTec LLC. On this page, "I", "me" and "my" mean LTCLevTec LLC.`,
    [
    "I only get your Roblox UserId. Never your password or email.",
    "Your lists are seen by you and the people you share them with. Nobody else.",
    "I don't sell your data, and there are no ads.",
    "Message me in my Discord and I'll delete everything.",
    ],
    `<h2>What I collect</h2>
<p><b>Your Roblox UserId.</b> Roblox gives it to me when you log in. It's how lists know who owns them and who they're shared with.</p>
<p><b>Whether you own CheckpointLTC.</b> When you log in, and about once a day after that, I ask Roblox whether your account owns the plugin. I only look for CheckpointLTC, nothing else in your inventory.</p>
<p><b>Your lists.</b> List names, tasks and their details (priority, due dates, labels, sections, notes, Studio links), comments, who you share them with and who tasks are assigned to.</p>
<p><b>Activity.</b> A log of changes on each list (who changed what and when), kept for up to 90 days or the last 500 changes per list, so collaborators can see history and undo mistakes.</p>
<p><b>Preferences.</b> Your plugin settings, so they follow you to other computers.</p>
<p><b>Public Roblox profile names.</b> Usernames and display names for the people on your lists, read from Roblox's public API so lists show names instead of numbers.</p>
<p><b>Reports you send.</b> Bug reports and feedback you send from the plugin, including any file you attach.</p>
<p><b>In game reports.</b> If a game owner sets up CheckpointLTC reports, the game can send me a player's UserId, username and the text they typed. Games must run that text through Roblox's text filter first.</p>
<p>I never get your password or email, and nothing from your places except what you choose to link to a task.</p>

<h2>What I store and how</h2>
<p>Your UserId and your lists, in my database on Cloudflare. A private key for each computer you log in on, stored only as a hash. If you bought the plugin, a Roblox login token that lets me do the daily ownership check, stored encrypted. Your IP address is used for rate limiting and isn't stored.</p>

<h2>Files you attach</h2>
<p>Files attached to a bug report or feedback are uploaded to private storage on Cloudflare, never straight to a public place. Every file is scanned automatically for inappropriate content. Clean files are passed to my private support channel and then deleted from my storage. Files that are flagged are held privately for a person to review and are deleted when the review is done, or after 7 days at most, except where the law requires me to keep them (for example illegal content I must report to the authorities).</p>

<h2>Who sees it</h2>
<p>People you share a list with see that list. Nobody else. I don't sell or share your data, and there are no ads. My server runs on Cloudflare, and Roblox handles login and purchases under their own privacy policy.</p>
<p>These web pages (not the plugin) use Cloudflare Web Analytics to count visits, which uses no cookies and doesn't follow you to other sites, and Cloudflare's bot protection to block automated abuse.</p>

<h2>Removing your data</h2>
<p>Delete a list in the plugin and it's gone. To delete everything, message me in my <a href="${discord}">Discord</a> and I'll remove your account and lists. You can also remove CheckpointLTC from the apps connected to your Roblox account any time.</p>

<h2>Changes</h2>
<p>If this changes I'll update this page and the date above.</p>`,
    { href: "/terms", label: "Read the terms" },
  );
}

export async function terms(): Promise<Response> {
  return legalPage(
    "Terms of service",
    `Last updated ${updated}. By using CheckpointLTC you agree to these terms with LTCLevTec LLC, the company I run CheckpointLTC through. On this page, "I", "me" and "my" mean LTCLevTec LLC.`,
    [
    "Follow Roblox's rules and don't abuse the service.",
    "The code is public to read, not to copy, reupload or sell.",
    "Inappropriate uploads get a strike. Illegal content gets reported.",
    "It's provided as is, so keep a copy of anything critical.",
    ],
    `<h2>Using it</h2>
<p>You need a Roblox account and you have to follow Roblox's own terms. You log in with Roblox, and you're responsible for what goes in your lists. Don't use it for anything illegal, abusive, or against Roblox's rules, and don't try to get into lists that aren't shared with you or overload the service.</p>

<h2>Buying it</h2>
<p>CheckpointLTC is sold through the Roblox Creator Store. Payments and refunds go through Roblox. Each Roblox account needs its own copy, including teammates you share lists with. If a purchase is refunded, access ends. All sales are final: I don't give refunds, and any refund is only what Roblox itself decides under its own policies.</p>

<h2>The code</h2>
<p>The source code is public so you can see how it works, but it isn't free to copy, reupload or sell. See the license in the repository.</p>

<h2>No guarantees</h2>
<p>I work to keep it running and your lists safe, but it's provided as is. I'm not liable for lost data or downtime. Keep anything critical somewhere else too.</p>

<h2>Uploaded files</h2>
<p>Every file you attach is automatically moderated and checked. Uploading inappropriate content results in an immediate strike and a permanent ban from uploading files. You can still use the plugin and send reports without attachments. Severe violations result in a ban from CheckpointLTC entirely. Illegal content will be reported to the authorities.</p>

<h2>Ending access</h2>
<p>I can suspend or ban accounts that break these terms. A banned account can't log in, but lists it owns stay available to the people they were shared with. If your account gets a strike, an upload ban or a full ban for breaking these terms, you are not entitled to a refund for the plugin or for any time you couldn't use it. If CheckpointLTC ever shuts down, I'll give notice in my Discord first.</p>

<h2>Changes</h2>
<p>If these change I'll update this page and the date above.</p>`,
    { href: "/privacy", label: "Read the privacy policy" },
  );
}
