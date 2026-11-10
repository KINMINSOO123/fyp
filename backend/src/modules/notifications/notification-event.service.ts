import type { NotificationType } from "./notification.types.js";
import { FcmPushAdapter } from "./fcm-push.adapter.js";
import type { NotificationEventRepo } from "./notification-event.repo.js";

export type BusinessEvent = { type: NotificationType;
  severity: "INFO" | "WARNING" | "CRITICAL";
  title: string; message: string; eventKey: string;
  relatedEntityType?: string; relatedEntityId?: string };

const rolesByType: Record<NotificationType, string[]> = {
  LOW_STOCK: ["BAKERY_MANAGER", "SYSTEM_ADMINISTRATOR"],
  EXPIRING_BATCH: ["BAKERY_MANAGER", "SYSTEM_ADMINISTRATOR"],
  EXPIRED_BATCH: ["BAKERY_MANAGER", "SYSTEM_ADMINISTRATOR"],
  LOW_CONFIDENCE: ["BAKERY_MANAGER"],
  LOST_SALES: ["BAKERY_MANAGER"],
  EXCESSIVE_LEFTOVER: ["BAKERY_MANAGER"],
  DONATION_STATUS: ["BAKERY_MANAGER"],
  MODEL_OPERATION_FAILURE: ["SYSTEM_ADMINISTRATOR"],
  EXTERNAL_SERVICE_FAILURE: ["BAKERY_MANAGER", "SYSTEM_ADMINISTRATOR"],
  SYSTEM_FAILURE: ["SYSTEM_ADMINISTRATOR"],
  ADMINISTRATIVE_EVENT: ["SYSTEM_ADMINISTRATOR"],
};
type EventRepo = Pick<NotificationEventRepo, "recipients" | "insert" |
  "tokens" | "skip" | "pending" | "submitted" | "failed" |
  "deactivateToken">;

export class NotificationEventService {
  constructor(private readonly providedRepo?: EventRepo,
    private readonly push: Pick<FcmPushAdapter, "send"> = new FcmPushAdapter()) {}

  private async repo(): Promise<EventRepo> {
    return this.providedRepo ?? new (
      await import("./notification-event.repo.js")
    ).NotificationEventRepo();
  }

  async publish(event: BusinessEvent): Promise<void> {
    if (!event.eventKey.trim() || event.eventKey.length > 200 ||
        !event.title.trim() || !event.message.trim() ||
        event.title.length > 120 || event.message.length > 500 ||
        (event.relatedEntityType === undefined) !==
          (event.relatedEntityId === undefined)) {
      throw new Error("Invalid internal notification event.");
    }
    const repo = await this.repo();
    const recipients = await repo.recipients(event.type,
      rolesByType[event.type]);
    for (const recipient of recipients) {
      const saved = await repo.insert(recipient.userId, {
        type: event.type, severity: event.severity, title: event.title,
        message: event.message,
        relatedEntityType: event.relatedEntityType ?? null,
        relatedEntityId: event.relatedEntityId ?? null,
        eventKey: event.eventKey,
      });
      if (!saved.created) continue;
      if (!recipient.pushEnabled) {
        await repo.skip(saved.id, "PUSH_NOT_OPTED_IN");
        continue;
      }
      const tokens = await repo.tokens(recipient.userId);
      if (!tokens.length) {
        await repo.skip(saved.id, "NO_ACTIVE_RECIPIENT_TOKEN");
        continue;
      }
      for (const token of tokens) {
        const deliveryId = await repo.pending(saved.id, token.id);
        try {
          const submitted = await this.push.send(token.token,
            event.title, event.message);
          await repo.submitted(deliveryId, submitted.providerMessageId);
        } catch (error) {
          const reason = error instanceof Error &&
            ["FCM_NOT_CONFIGURED", "FCM_AUTH_FAILED", "FCM_UNREGISTERED",
              "FCM_SUBMISSION_FAILED"].includes(error.message) ?
              error.message : "FCM_UNAVAILABLE";
          await repo.failed(deliveryId, reason);
          if (reason === "FCM_UNREGISTERED") {
            await repo.deactivateToken(token.id, recipient.userId);
          }
        }
      }
    }
  }
}
