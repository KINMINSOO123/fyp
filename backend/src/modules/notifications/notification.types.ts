export const notificationTypes = [
  "LOW_STOCK", "EXPIRING_BATCH", "EXPIRED_BATCH", "LOW_CONFIDENCE",
  "LOST_SALES", "EXCESSIVE_LEFTOVER", "DONATION_STATUS",
  "MODEL_OPERATION_FAILURE", "EXTERNAL_SERVICE_FAILURE", "SYSTEM_FAILURE",
  "ADMINISTRATIVE_EVENT",
] as const;
export type NotificationType = typeof notificationTypes[number];
export type NotificationPreference = {
  notificationType: NotificationType;
  inAppEnabled: boolean;
  pushEnabled: boolean;
};
export type NotificationItem = {
  id: string; notificationType: NotificationType;
  severity: "INFO" | "WARNING" | "CRITICAL";
  title: string; message: string;
  relatedEntityType: string | null; relatedEntityId: string | null;
  isRead: boolean; readAt: string | null; createdAt: string;
};

export function isNotificationType(value: unknown): value is NotificationType {
  return typeof value === "string" &&
    (notificationTypes as readonly string[]).includes(value);
}
