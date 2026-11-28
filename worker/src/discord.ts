import type { Env } from "./env";
import { ApiError } from "./http";

export type SubmissionKind = "bug" | "feedback";

interface TagSet {
  fromPlugin?: string;
  held?: string;
}

interface TagConfig {
  bug?: TagSet;
  feedback?: TagSet;
}

export const brandRed = 0x7a0e1c;
export const brandBlue = 0x29b9e8;

export interface Post {
  kind: SubmissionKind;
  userId: number;
  username: string;
  displayName: string;
  title: string;
  body: string;
  steps: string | null;
  category: string | null;
  pluginVersion: string | null;
  studioInfo: string | null;
  attachment: { name: string; bytes: Uint8Array; mime: string } | null;
  heldReviewUrl: string | null;
}

function webhookFor(env: Env, kind: SubmissionKind): string {
  return kind === "bug" ? env.DISCORD_BUG_WEBHOOK : env.DISCORD_FEEDBACK_WEBHOOK;
}

export function discordReady(env: Env, kind: SubmissionKind): boolean {
  return env.environmentName === "local" || Boolean(webhookFor(env, kind));
}

function tagsFor(env: Env, post: Post): string[] {
  let config: TagConfig = {};
  try {
    config = JSON.parse(env.discordTags || "{}") as TagConfig;
  } catch {
    config = {};
  }
  const set = (post.kind === "bug" ? config.bug : config.feedback) ?? {};
  const tags = [set.fromPlugin, post.heldReviewUrl ? set.held : undefined];
  return tags.filter((t): t is string => typeof t === "string" && /^\d{5,25}$/.test(t));
}

async function headshot(userId: number): Promise<string | undefined> {
  try {
    const response = await fetch(
      `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${userId}&size=150x150&format=Png&isCircular=false`,
      { signal: AbortSignal.timeout(4000) },
    );
    const data = (await response.json()) as { data?: { imageUrl?: string }[] };
    return data.data?.[0]?.imageUrl;
  } catch {
    return undefined;
  }
}

const clip = (text: string, max: number) => (text.length > max ? `${text.slice(0, max - 1)}…` : text);

export async function postSubmission(env: Env, post: Post): Promise<{ threadId: string | null }> {
  const test = env.environmentName !== "production";
  const date = new Date();
  const label = post.kind === "bug" ? "Bug Report" : "Feedback";
  const threadName = clip(`${test ? "[Test] " : ""}${label} · ${post.username} · ${date.toISOString().slice(0, 10)}`, 100);

  const fields = [
    { name: "UserId", value: String(post.userId), inline: true },
    { name: "Date", value: `<t:${Math.floor(date.getTime() / 1000)}:f>`, inline: true },
    { name: "Plugin version", value: post.pluginVersion ?? "Not shared", inline: true },
    { name: "Environment", value: test ? `${env.environmentName} (Test)` : "Production", inline: true },
  ];
  if (post.category) fields.push({ name: "Category", value: post.category, inline: true });
  if (post.studioInfo) fields.push({ name: "Studio info", value: clip(post.studioInfo, 1024), inline: false });
  if (post.steps) fields.push({ name: "Steps to reproduce", value: clip(post.steps, 1024), inline: false });
  if (post.heldReviewUrl) {
    fields.push({ name: "Attachment held for review", value: "The file is waiting for a manual check before it shows here.", inline: false });
  } else if (post.attachment) {
    fields.push({ name: "Attachment", value: post.attachment.name, inline: false });
  }

  const avatar = await headshot(post.userId);
  const embed = {
    author: {
      name: post.displayName && post.displayName !== post.username ? `${post.displayName} (@${post.username})` : `@${post.username}`,
      url: `https://www.roblox.com/users/${post.userId}/profile`,
      ...(avatar ? { icon_url: avatar } : {}),
    },
    title: clip(post.title, 256),
    description: clip(post.body, 4000),
    color: post.kind === "bug" ? brandRed : brandBlue,
    fields,
    footer: { text: "CheckpointLTC" },
    timestamp: date.toISOString(),
  };
  const payload = {
    thread_name: threadName,
    applied_tags: tagsFor(env, post),
    embeds: [embed],
    allowed_mentions: { parse: [] },
  };

  if (env.environmentName === "local") {
    console.log("discord post (local)", JSON.stringify({ ...payload, attachment: post.attachment?.name ?? null }));
    return { threadId: "local" };
  }

  const form = new FormData();
  form.set("payload_json", JSON.stringify(payload));
  if (post.attachment) form.set("files[0]", new Blob([post.attachment.bytes], { type: post.attachment.mime }), post.attachment.name);
  const response = await fetch(`${webhookFor(env, post.kind)}?wait=true`, { method: "POST", body: form });
  if (!response.ok) {
    console.error("discord post failed", response.status, await response.text());
    throw new ApiError("unavailable", "I couldn't deliver that right now. Try again in a few minutes.");
  }
  const message = (await response.json()) as { channel_id?: string };
  return { threadId: message.channel_id ?? null };
}

export async function postToThread(
  env: Env,
  kind: SubmissionKind,
  threadId: string,
  content: string,
  file: { name: string; bytes: Uint8Array; mime: string } | null,
): Promise<void> {
  if (env.environmentName === "local") {
    console.log("discord thread post (local)", threadId, content, file?.name ?? "");
    return;
  }
  const form = new FormData();
  form.set("payload_json", JSON.stringify({ content, allowed_mentions: { parse: [] } }));
  if (file) form.set("files[0]", new Blob([file.bytes], { type: file.mime }), file.name);
  const response = await fetch(`${webhookFor(env, kind)}?wait=true&thread_id=${encodeURIComponent(threadId)}`, { method: "POST", body: form });
  if (!response.ok) throw new ApiError("unavailable", "Discord did not accept the message.");
}

export async function reviewAlert(env: Env, text: string): Promise<void> {
  const hook = env.DISCORD_ALERT_WEBHOOK || env.DISCORD_BUG_WEBHOOK;
  if (env.environmentName === "local" || !hook) {
    console.log("review alert (local)", text);
    return;
  }
  await fetch(hook, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      content: `${env.environmentName === "production" ? "" : "[Test] "}${text}`,
      allowed_mentions: { parse: [] },
      ...(env.DISCORD_ALERT_WEBHOOK ? {} : { thread_name: "Attachment held for review" }),
    }),
  }).catch((err) => console.error("review alert failed", err));
}

export interface AlertField {
  name: string;
  value: string;
  inline?: boolean;
}

export async function detailAlert(env: Env, title: string, description: string, fields: AlertField[]): Promise<void> {
  const hook = env.DISCORD_ALERT_WEBHOOK;
  if (env.environmentName === "local" || !hook) {
    console.error("ALERT", title, JSON.stringify(fields));
    return;
  }
  await fetch(hook, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      content: `🚨 ${env.environmentName === "production" ? "" : "[Test] "}**${title}**`,
      allowed_mentions: { parse: [] },
      embeds: [
        {
          color: brandRed,
          description: description.slice(0, 4000),
          fields: fields.slice(0, 25).map((f) => ({ name: f.name.slice(0, 256), value: (f.value || "unknown").slice(0, 1024), inline: f.inline ?? false })),
          timestamp: new Date().toISOString(),
        },
      ],
    }),
  }).catch((err) => console.error("detail alert failed", err));
}

export async function urgentAlert(env: Env, text: string): Promise<void> {
  const hook = env.DISCORD_ALERT_WEBHOOK || env.DISCORD_BUG_WEBHOOK;
  if (env.environmentName === "local" || !hook) {
    console.error("URGENT", text);
    return;
  }
  await fetch(hook, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      content: `🚨 **Urgent: illegal content report needed.** ${text}`,
      allowed_mentions: { parse: [] },
      ...(env.DISCORD_ALERT_WEBHOOK ? {} : { thread_name: "URGENT · illegal content" }),
    }),
  }).catch((err) => console.error("urgent alert failed", err));
}
