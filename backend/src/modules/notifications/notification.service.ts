import { AppError } from "../../shared/AppError.js";
import type { NotificationRepo } from "./notification.repo.js";
import { isNotificationType } from "./notification.types.js";
import type { NotificationType } from "./notification.types.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type DataRepo = Pick<NotificationRepo, "preferences" | "savePreference" |
  "list" | "markRead" | "registerToken" | "deactivateToken" | "deliveries">;

function id(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) {
    throw new AppError(400, "VALIDATION_ERROR", "A valid ID is required.");
  }
  return value;
}
function object(raw: unknown, keys: string[]): Record<string, unknown> {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw) ||
      Object.keys(raw).some((key) => !keys.includes(key))) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid notification fields.");
  }
  return raw as Record<string, unknown>;
}

export class NotificationService {
  constructor(private readonly providedRepo?: DataRepo) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./notification.repo.js")
    ).NotificationRepo();
  }

  async preferences(userId: string) {
    return (await this.repo()).preferences(userId);
  }
  async savePreference(userId: string, raw: unknown) {
    const input = object(raw,
      ["notificationType", "inAppEnabled", "pushEnabled"]);
    if (Object.keys(input).length !== 3 ||
        !isNotificationType(input.notificationType) ||
        typeof input.inAppEnabled !== "boolean" ||
        typeof input.pushEnabled !== "boolean") {
      throw new AppError(400, "VALIDATION_ERROR",
        "A valid notification type and two Boolean preferences are required.");
    }
    return (await this.repo()).savePreference(userId, {
      notificationType: input.notificationType,
      inAppEnabled: input.inAppEnabled,
      pushEnabled: input.pushEnabled,
    });
  }
  async list(userId: string, raw: unknown) {
    const query = object(raw, ["page", "unreadOnly"]);
    const page = query.page === undefined ? 1 : Number(query.page);
    if (query.page !== undefined &&
        (typeof query.page !== "string" || !/^[1-9]\d*$/.test(query.page)) ||
        !Number.isSafeInteger(page) || page < 1 || page > 42_949_672 ||
        (query.unreadOnly !== undefined && query.unreadOnly !== "true" &&
         query.unreadOnly !== "false")) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid notification filters.");
    }
    const repo = await this.repo();
    const preferences = await repo.preferences(userId);
    const visible = preferences.filter((pref) => pref.inAppEnabled)
      .map((pref) => pref.notificationType as NotificationType);
    return repo.list(userId, page, query.unreadOnly === "true", visible);
  }
  async markRead(userId: string, notificationId: string, raw: unknown) {
    const input = object(raw, []);
    if (Object.keys(input).length) throw new AppError(400,
      "VALIDATION_ERROR", "Mark-read accepts no fields.");
    return (await this.repo()).markRead(userId, id(notificationId));
  }
  async deliveries(userId: string, notificationId: string) {
    return (await this.repo()).deliveries(userId, id(notificationId));
  }
  async registerToken(userId: string, raw: unknown) {
    const input = object(raw, ["token", "deviceInfo"]);
    if (typeof input.token !== "string" || !input.token.trim() ||
        input.token.length > 4096 ||
        (input.deviceInfo !== undefined && input.deviceInfo !== null &&
         (typeof input.deviceInfo !== "string" ||
          input.deviceInfo.length > 200))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid device token.");
    }
    return (await this.repo()).registerToken(userId, input.token.trim(),
      typeof input.deviceInfo === "string" ?
        input.deviceInfo.trim() || null : null);
  }
  async deactivateToken(userId: string, tokenId: string) {
    await (await this.repo()).deactivateToken(userId, id(tokenId));
  }
}
