export interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  apiLimiter: RateLimit;
  authLimiter: RateLimit;
  pollLimiter: RateLimit;
  ipLimiter: RateLimit;
  latestPluginVersion: string;
  minPluginVersion: string;
  requireVerification: string;
  publicOrigin: string;
  ROBLOX_CLIENT_ID: string;
  pluginAssetId: string;
  TOKEN_KEY: string;
  ROBLOX_CLIENT_SECRET: string;
  UPLOADS: R2Bucket;
  AI: Ai;
  MEDIA: MediaBinding;
  gameLimiter: RateLimit;
  gameIpLimiter: RateLimit;
  bulkLimiter: RateLimit;
  GAME_FLOOD_RULE?: string;
  environmentName: "production" | "staging" | "local";
  moderationThresholds: string;
  discordTags: string;
  DISCORD_BUG_WEBHOOK: string;
  DISCORD_FEEDBACK_WEBHOOK: string;
  DISCORD_ALERT_WEBHOOK: string;
  REVIEW_PASSWORD: string;
}

export interface MediaBinding {
  input(stream: ReadableStream<Uint8Array>): {
    output(options: { mode: "frame"; time: string; format: "jpg" | "png" }): { response(): Promise<Response> };
  };
}

export type BanLevel = "upload" | "full" | "illegal";

export interface Caller {
  userId: number;
  sessionId: string;
  banLevel: BanLevel | null;
}
