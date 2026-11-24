import type { Env } from "./env";
import { limits, moderationCategories, type ModerationCategory } from "./config";

export type Scores = Record<ModerationCategory, number>;

export interface Verdict {
  status: "clean" | "flagged" | "unchecked";
  scores: Scores;
  worst: ModerationCategory | null;
  reason: string;
}

const visionModel = "@cf/meta/llama-3.2-11b-vision-instruct";
const textModel = "@cf/meta/llama-guard-3-8b";

const zero = (): Scores => Object.fromEntries(moderationCategories.map((c) => [c, 0])) as Scores;

const prompt = `Look at this image, which a game developer attached to a bug report.
Is it fine to show in a support channel for a general audience? Game screenshots, code, interface, error messages and cartoon game combat are fine.
Answer with only JSON: {"fine": true or false, "category": one of "none", "sexual", "violence", "gore", "hate", "selfharm", "illegal", "confidence": a number from 0 to 1}.`;

export function thresholds(env: Env): Scores {
  const fallback: Scores = { sexual: 0.4, minors: 0.15, violence: 0.7, gore: 0.6, hate: 0.5, selfharm: 0.5, illegal: 0.5 };
  try {
    const parsed = JSON.parse(env.moderationThresholds || "{}") as Partial<Scores>;
    for (const c of moderationCategories) if (typeof parsed[c] === "number") fallback[c] = parsed[c] as number;
  } catch {
    return fallback;
  }
  return fallback;
}

function parseScores(answer: unknown): Scores | null {
  let raw: Record<string, unknown>;
  try {
    if (answer && typeof answer === "object") {
      raw = answer as Record<string, unknown>;
    } else {
      const match = /\{[\s\S]*\}/.exec(String(answer ?? ""));
      if (!match) return null;
      raw = JSON.parse(match[0]) as Record<string, unknown>;
    }
    const scores = zero();
    if (typeof raw.fine !== "boolean") return null;
    if (raw.fine) return scores;
    const category = moderationCategories.find((c) => c === raw.category) ?? "illegal";
    const confidence = Number(raw.confidence);
    scores[category] = Number.isFinite(confidence) ? Math.min(1, Math.max(0, confidence)) : 1;
    return scores;
  } catch {
    return null;
  }
}

function judge(env: Env, scores: Scores, reason: string): Verdict {
  const limit = thresholds(env);
  let worst: ModerationCategory | null = null;
  let worstMargin = 0;
  for (const c of moderationCategories) {
    const margin = scores[c] - limit[c];
    if (margin >= 0 && (worst === null || margin > worstMargin)) {
      worst = c;
      worstMargin = margin;
    }
  }
  return { status: worst ? "flagged" : "clean", scores, worst, reason: worst ? `${worst} scored ${scores[worst].toFixed(2)}` : reason };
}

const merge = (all: Scores[]): Scores => {
  const out = zero();
  for (const s of all) for (const c of moderationCategories) out[c] = Math.max(out[c], s[c]);
  return out;
};

let lastRaw = "";

async function runVision(env: Env, bytes: Uint8Array): Promise<Scores | null> {
  const ask = () =>
    env.AI.run(visionModel as keyof AiModels, { prompt, image: [...bytes], max_tokens: 120, temperature: 0 } as never) as Promise<{
      response?: unknown;
    }>;
  let result: { response?: unknown };
  try {
    result = await ask();
  } catch (err) {
    if (!/agree/i.test(String(err))) throw err;
    await env.AI.run(visionModel as keyof AiModels, { prompt: "agree" } as never);
    result = await ask();
  }
  lastRaw = JSON.stringify(result.response ?? result).slice(0, 200);
  return parseScores(result.response);
}

function stubScores(bytes: Uint8Array): Scores {
  const text = new TextDecoder("latin1").decode(bytes);
  const scores = zero();
  if (text.includes("FLAGME")) scores.sexual = 0.99;
  return scores;
}

export async function moderateImage(env: Env, bytes: Uint8Array): Promise<Verdict> {
  if (env.environmentName === "local") return judge(env, stubScores(bytes), "stub check");
  try {
    const scores = await runVision(env, bytes);
    if (!scores) return { status: "unchecked", scores: zero(), worst: null, reason: `The checker gave an unreadable answer: ${lastRaw}` };
    return judge(env, scores, "image checked");
  } catch (err) {
    console.error("image moderation failed", err);
    return { status: "unchecked", scores: zero(), worst: null, reason: `The image checker failed: ${String(err).slice(0, 200)}` };
  }
}

export async function moderateVideo(env: Env, key: string): Promise<Verdict> {
  if (env.environmentName === "local") {
    const object = await env.UPLOADS.get(key);
    const bytes = new Uint8Array(object ? await object.arrayBuffer() : new ArrayBuffer(0));
    return judge(env, stubScores(bytes), "stub check");
  }
  const all: Scores[] = [];
  for (let frame = 0; frame < limits.videoMaxFrames; frame++) {
    const object = await env.UPLOADS.get(key);
    if (!object) break;
    let image: Response;
    try {
      image = await env.MEDIA.input(object.body)
        .output({ mode: "frame", time: `${frame * limits.videoFrameEverySeconds}s`, format: "jpg" })
        .response();
    } catch (err) {
      if (frame > 0) break;
      console.error("video frame failed", err);
      return { status: "unchecked", scores: zero(), worst: null, reason: "Could not read frames from this video." };
    }
    if (!image.ok) {
      if (frame > 0) break;
      return { status: "unchecked", scores: zero(), worst: null, reason: "Could not read frames from this video." };
    }
    const verdict = await moderateImage(env, new Uint8Array(await image.arrayBuffer()));
    if (verdict.status === "unchecked") return verdict;
    all.push(verdict.scores);
    if (verdict.status === "flagged") break;
  }
  if (all.length === 0) return { status: "unchecked", scores: zero(), worst: null, reason: "Could not read frames from this video." };
  return judge(env, merge(all), `${all.length} frames checked`);
}

export async function moderateText(env: Env, text: string): Promise<Verdict> {
  if (env.environmentName === "local") return judge(env, stubScores(new TextEncoder().encode(text)), "stub check");
  try {
    const result = (await env.AI.run(textModel as keyof AiModels, {
      messages: [{ role: "user", content: text.slice(0, 6000) }],
    } as never)) as { response?: string | { safe?: boolean; categories?: string[] } };
    const response = result.response;
    const unsafe =
      typeof response === "string" ? /unsafe/i.test(response) : response && typeof response === "object" ? response.safe === false : false;
    const scores = zero();
    if (unsafe) scores.illegal = 1;
    return unsafe
      ? { status: "flagged", scores, worst: "illegal", reason: "The text checker marked this file unsafe." }
      : { status: "clean", scores, worst: null, reason: "text checked" };
  } catch (err) {
    console.error("text moderation failed", err);
    return { status: "unchecked", scores: zero(), worst: null, reason: "The text checker failed." };
  }
}
