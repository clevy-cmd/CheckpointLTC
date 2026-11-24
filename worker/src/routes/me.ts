import type { Caller, Env } from "../env";
import { json } from "../http";
import { labels, limits, uploadTypes } from "../config";
import { isPaid } from "../oauth";
import { cooldowns } from "./submissions";
import { loadPreferences } from "./preferences";

interface OwnedRow {
  id: string;
  title: string;
  item_count: number;
  members: number;
  assigned: number;
}

export async function me(_request: Request, env: Env, caller: Caller): Promise<Response> {
  const owned = await env.DB.prepare(
    `SELECT l.id, l.title, l.item_count,
            (SELECT COUNT(*) FROM members m WHERE m.list_id = l.id) AS members,
            (SELECT COUNT(*) FROM assignments a WHERE a.list_id = l.id) AS assigned
       FROM lists l
      WHERE l.owner_id = ? AND l.deleted_at IS NULL
      ORDER BY l.updated_at DESC`,
  )
    .bind(caller.userId)
    .all<OwnedRow>();
  const ready = await cooldowns(env, caller.userId);
  const now = Date.now();
  const preferences = await loadPreferences(env, caller.userId);

  return json({
    userId: caller.userId,
    plan: isPaid(env) ? "paid" : "free",
    environment: env.environmentName,
    limits: {
      listsOwned: limits.listsPerOwner,
      itemsPerList: limits.itemsPerList,
      editorsPerList: limits.membersPerList,
      assignedPerList: limits.assignmentsPerList,
      titleMaxLength: limits.titleMaxLength,
      itemMaxLength: limits.itemMaxLength,
      notesMaxLength: limits.notesMaxLength,
      commentMaxLength: limits.commentMaxLength,
      sectionMaxLength: limits.sectionMaxLength,
      submissionTitleMaxLength: limits.submissionTitleMaxLength,
      submissionBodyMaxLength: limits.submissionBodyMaxLength,
      bugReportsPerHour: 1,
      feedbackPerHour: 1,
      attachmentMaxBytes: limits.uploadMaxBytes,
      attachmentsPerSubmission: 1,
      attachmentTypes: Object.keys(uploadTypes).filter((t) => t !== "jpeg"),
      uploadChunkBytes: limits.uploadChunkBytes,
      gameReportMaxLength: limits.gameReportMaxLength,
      trashDays: Math.round(limits.trashMs / 86_400_000),
      labels,
    },
    usage: {
      listsOwned: owned.results.length,
      lists: owned.results.map((r) => ({
        id: r.id,
        title: r.title,
        items: r.item_count,
        editors: r.members,
        assigned: r.assigned,
      })),
    },
    cooldowns: {
      bugAvailableAt: ready.bug > now ? ready.bug : null,
      feedbackAvailableAt: ready.feedback > now ? ready.feedback : null,
    },
    uploads: caller.banLevel ? "blocked" : "allowed",
    uploadWarningAccepted: preferences.uploadWarningAccepted,
    serverTime: now,
  });
}
