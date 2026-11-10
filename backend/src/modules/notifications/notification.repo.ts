import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import { notificationTypes } from "./notification.types.js";
import type { NotificationItem, NotificationPreference,
  NotificationType } from "./notification.types.js";

export class NotificationRepo {
  async preferences(userId: string): Promise<NotificationPreference[]> {
    const { data, error } = await supabaseAdmin.from("notification_preferences")
      .select("notification_type,in_app_enabled,push_enabled")
      .eq("user_id", userId);
    if (error || !data) throw new AppError(503,
      "NOTIFICATION_DATA_UNAVAILABLE", "Unable to load notification preferences.");
    const stored = new Map(data.map((row) => [row.notification_type, row]));
    return notificationTypes.map((type) => ({ notificationType: type,
      inAppEnabled: stored.get(type)?.in_app_enabled ?? true,
      pushEnabled: stored.get(type)?.push_enabled ?? false }));
  }

  async savePreference(userId: string, preference: NotificationPreference):
    Promise<NotificationPreference> {
    const { error } = await supabaseAdmin.from("notification_preferences")
      .upsert({ user_id: userId,
        notification_type: preference.notificationType,
        in_app_enabled: preference.inAppEnabled,
        push_enabled: preference.pushEnabled },
      { onConflict: "user_id,notification_type" });
    if (error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to save notification preference.");
    return preference;
  }

  async list(userId: string, page: number, unreadOnly: boolean,
    visibleTypes: NotificationType[]) {
    if (!visibleTypes.length) return { page, pageSize: 50, total: 0, items: [] };
    let query = supabaseAdmin.from("notifications")
      .select("id,notification_type,severity,title,message,related_entity_type,related_entity_id,is_read,read_at,created_at",
        { count: "exact" })
      .eq("recipient_user_id", userId)
      .in("notification_type", visibleTypes);
    if (unreadOnly) query = query.eq("is_read", false);
    const { data, count, error } = await query
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range((page - 1) * 50, page * 50 - 1);
    if (error || !data || count === null) throw new AppError(503,
      "NOTIFICATION_DATA_UNAVAILABLE", "Unable to load notifications.");
    const items: NotificationItem[] = data.map((row) => ({
      id: row.id, notificationType: row.notification_type as NotificationType,
      severity: row.severity, title: row.title, message: row.message,
      relatedEntityType: row.related_entity_type,
      relatedEntityId: row.related_entity_id,
      isRead: row.is_read, readAt: row.read_at, createdAt: row.created_at,
    }));
    return { page, pageSize: 50, total: count, items };
  }

  async markRead(userId: string, notificationId: string): Promise<NotificationItem> {
    const changed = await supabaseAdmin.from("notifications")
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq("id", notificationId).eq("recipient_user_id", userId)
      .eq("is_read", false)
      .select("id,notification_type,severity,title,message,related_entity_type,related_entity_id,is_read,read_at,created_at")
      .maybeSingle();
    if (changed.error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to update notification.");
    const existing = changed.data ? changed : await supabaseAdmin.from("notifications")
      .select("id,notification_type,severity,title,message,related_entity_type,related_entity_id,is_read,read_at,created_at")
      .eq("id", notificationId).eq("recipient_user_id", userId)
      .maybeSingle();
    if (existing.error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to load notification.");
    const data = existing.data;
    if (!data) throw new AppError(404, "NOTIFICATION_NOT_FOUND",
      "Notification not found for this user.");
    return { id: data.id, notificationType: data.notification_type,
      severity: data.severity, title: data.title, message: data.message,
      relatedEntityType: data.related_entity_type,
      relatedEntityId: data.related_entity_id, isRead: data.is_read,
      readAt: data.read_at, createdAt: data.created_at };
  }

  async registerToken(userId: string, token: string, deviceInfo: string | null) {
    const existing = await supabaseAdmin.from("fcm_tokens")
      .select("id,user_id").eq("token", token).maybeSingle();
    if (existing.error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to check device token.");
    if (existing.data && existing.data.user_id !== userId) {
      throw new AppError(409, "FCM_TOKEN_OWNED_BY_OTHER_USER",
        "This device token is registered to another user.");
    }
    const query = existing.data ? supabaseAdmin.from("fcm_tokens")
      .update({ is_active: true, device_info: deviceInfo })
      .eq("id", existing.data.id).eq("user_id", userId) :
      supabaseAdmin.from("fcm_tokens").insert({ user_id: userId,
        token, device_info: deviceInfo, is_active: true });
    const { data, error } = await query.select("id").single();
    if (error?.code === "23505") throw new AppError(409,
      "FCM_TOKEN_OWNED_BY_OTHER_USER",
      "This device token is already registered.");
    if (error || !data) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to register device token.");
    return { id: data.id };
  }

  async deactivateToken(userId: string, tokenId: string): Promise<void> {
    const { data, error } = await supabaseAdmin.from("fcm_tokens")
      .update({ is_active: false }).eq("id", tokenId).eq("user_id", userId)
      .select("id").maybeSingle();
    if (error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to unregister device token.");
    if (!data) throw new AppError(404, "FCM_TOKEN_NOT_FOUND",
      "Device registration not found for this user.");
  }

  async deliveries(userId: string, notificationId: string) {
    const owned = await supabaseAdmin.from("notifications").select("id")
      .eq("id", notificationId).eq("recipient_user_id", userId).maybeSingle();
    if (owned.error) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to load notification deliveries.");
    if (!owned.data) throw new AppError(404, "NOTIFICATION_NOT_FOUND",
      "Notification not found for this user.");
    const { data, error } = await supabaseAdmin.from("notification_deliveries")
      .select("id,push_status,attempt_number,attempted_at,delivered_at,failure_reason,skip_reason")
      .eq("notification_id", notificationId)
      .order("attempt_number", { ascending: true });
    if (error || !data) throw new AppError(503, "NOTIFICATION_DATA_UNAVAILABLE",
      "Unable to load notification deliveries.");
    return data.map((row) => ({ id: row.id, status: row.push_status,
      attemptNumber: row.attempt_number, attemptedAt: row.attempted_at,
      deliveredAt: row.delivered_at, failureReason: row.failure_reason,
      skipReason: row.skip_reason }));
  }
}
