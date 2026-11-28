export const limits = {
  maxBodyBytes: 8 * 1024,
  titleMaxLength: 60,
  itemMaxLength: 240,
  listsPerOwner: 50,
  itemsPerList: 500,
  membersPerList: 50,
  assignmentsPerList: 50,
  loginTtlMs: 10 * 60 * 1000,
  loginPollSeconds: 3,
  robloxLookupTimeoutMs: 4000,
  robloxOAuthTimeoutMs: 8000,
  licenceRecheckMs: 24 * 60 * 60 * 1000,
  licenceRetryMs: 60 * 60 * 1000,
  sessionsPerUser: 10,
  sessionLabelMaxLength: 40,
  activityPerList: 500,
  activityMaxAgeMs: 90 * 24 * 60 * 60 * 1000,
  editorActivityCount: 50,
  commentMaxLength: 1000,
  commentsPerItem: 200,
  notesMaxLength: 2000,
  sectionMaxLength: 40,
  linkMaxLength: 400,
  searchMaxResults: 100,
  myTasksMaxResults: 300,
  trashMs: 30 * 24 * 60 * 60 * 1000,
  presenceTtlMs: 2 * 60 * 1000,
  exportTtlMs: 10 * 60 * 1000,
  importMaxItems: 500,
  importMaxBytes: 256 * 1024,
  userCacheMs: 7 * 24 * 60 * 60 * 1000,
  submissionCooldownMs: 60 * 60 * 1000,
  submissionTitleMaxLength: 100,
  submissionBodyMaxLength: 2000,
  uploadMaxBytes: 10 * 1024 * 1024,
  uploadChunkBytes: 256 * 1024,
  uploadChunkBodyBytes: 400 * 1024,
  uploadPendingMs: 60 * 60 * 1000,
  heldUploadMs: 7 * 24 * 60 * 60 * 1000,
  videoFrameEverySeconds: 2,
  videoMaxFrames: 30,
  gameReportMaxLength: 500,
  gameReportCooldownMs: 60 * 60 * 1000,
  gameReportsPerHour: 120,
  gameReportsWaiting: 300,
  gameKeysPerList: 5,
  gameAttemptsKeptMs: 60 * 60 * 1000,
  notificationsMax: 100,
  notificationMaxAgeMs: 30 * 24 * 60 * 60 * 1000,
} as const;

export const labels = ["Scripting", "UI", "VFX", "Bug"] as const;
export type Label = (typeof labels)[number];

export const uploadTypes: Record<string, { mime: string; kind: "image" | "video" | "text" }> = {
  png: { mime: "image/png", kind: "image" },
  jpg: { mime: "image/jpeg", kind: "image" },
  jpeg: { mime: "image/jpeg", kind: "image" },
  mp4: { mime: "video/mp4", kind: "video" },
  mov: { mime: "video/quicktime", kind: "video" },
  txt: { mime: "text/plain", kind: "text" },
};

export const moderationCategories = ["sexual", "minors", "violence", "gore", "hate", "selfharm", "illegal"] as const;
export type ModerationCategory = (typeof moderationCategories)[number];

export const templates: Record<string, { title: string; sections: { name: string; items: string[] }[] }> = {
  launch: {
    title: "Game launch checklist",
    sections: [
      { name: "Gameplay", items: ["Full playtest with a fresh account", "Check every badge and game pass", "Balance pass on rewards"] },
      { name: "Polish", items: ["Thumbnail and icon", "Game description and tags", "Mobile controls check"] },
      { name: "Tech", items: ["Data stores tested with real players", "Error logs clean in the Developer Console", "Server size and streaming settings"] },
      { name: "Launch", items: ["Set the game to public", "Announce in the group and Discord", "Watch analytics for the first day"] },
    ],
  },
  triage: {
    title: "Bug triage",
    sections: [
      { name: "New", items: ["Reproduce the bug", "Note the device and platform"] },
      { name: "Fixing", items: ["Find the cause", "Write the fix"] },
      { name: "Verify", items: ["Test the fix in a live server", "Close the report"] },
    ],
  },
};

export const bannedMessage = "This account has been banned from CheckpointLTC for violating the Terms of Service.";

export const defaultSessionLabel = "Roblox Studio";

export const shareCodeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const shareCodeLength = 8;

export const idAlphabet = "abcdefghijkmnpqrstuvwxyz23456789";
export const idLength = 14;

export const keyPrefix = "ltc_";
export const keyBytes = 32;
