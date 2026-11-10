import { supabaseAdmin } from "../../config/supabase.js";
import type { NotificationType } from "./notification.types.js";

export type EventRecipient = { userId: string; inAppEnabled: boolean;
  pushEnabled: boolean };
export type ActiveToken = { id: string; token: string };

export class NotificationEventRepo {
  async recipients(type: NotificationType, roles: string[]):
    Promise<EventRecipient[]> {
    const profiles = await supabaseAdmin.from("user_profiles")
      .select("user_id,role").eq("account_status", "ACTIVE")
      .in("role", roles);
    if (profiles.error || !profiles.data) throw new Error(
      "Unable to identify notification recipients.");
    if (!profiles.data.length) return [];
    const preferences = await supabaseAdmin.from("notification_preferences")
      .select("user_id,in_app_enabled,push_enabled")
      .eq("notification_type", type)
      .in("user_id", profiles.data.map((row) => row.user_id));
    if (preferences.error || !preferences.data) throw new Error(
      "Unable to load recipient preferences.");
    const byUser = new Map(preferences.data.map((row) => [row.user_id, row]));
    return profiles.data.map((profile) => {
      const preference = byUser.get(profile.user_id);
      return { userId: profile.user_id,
        inAppEnabled: preference?.in_app_enabled ?? true,
        pushEnabled: preference?.push_enabled ?? false };
    }).filter((recipient) => recipient.inAppEnabled || recipient.pushEnabled);
  }

  async insert(recipientId: string, input: { type: NotificationType;
    severity: "INFO" | "WARNING" | "CRITICAL"; title: string;
    message: string; relatedEntityType: string | null;
    relatedEntityId: string | null; eventKey: string }):
    Promise<{ id: string; created: boolean }> {
    const inserted = await supabaseAdmin.from("notifications").insert({
      recipient_user_id: recipientId, notification_type: input.type,
      severity: input.severity, title: input.title, message: input.message,
      related_entity_type: input.relatedEntityType,
      related_entity_id: input.relatedEntityId,
      event_key: input.eventKey,
    }).select("id").single();
    if (!inserted.error && inserted.data) return {
      id: inserted.data.id, created: true };
    if (inserted.error?.code !== "23505") throw new Error(
      "Unable to save notification event.");
    const existing = await supabaseAdmin.from("notifications").select("id")
      .eq("recipient_user_id", recipientId)
      .eq("notification_type", input.type)
      .eq("event_key", input.eventKey).single();
    if (existing.error || !existing.data) throw new Error(
      "Unable to resolve duplicate notification event.");
    return { id: existing.data.id, created: false };
  }

  async tokens(recipientId: string): Promise<ActiveToken[]> {
    const { data, error } = await supabaseAdmin.from("fcm_tokens")
      .select("id,token").eq("user_id", recipientId).eq("is_active", true);
    if (error || !data) throw new Error("Unable to load recipient devices.");
    return data;
  }

  async skip(notificationId: string, reason: string): Promise<void> {
    const { error } = await supabaseAdmin.from("notification_deliveries")
      .insert({ notification_id: notificationId, fcm_token_id: null,
        push_status: "SKIPPED", skip_reason: reason });
    if (error) throw new Error("Unable to record skipped push delivery.");
  }

  async pending(notificationId: string, tokenId: string): Promise<string> {
    const { data, error } = await supabaseAdmin.from("notification_deliveries")
      .insert({ notification_id: notificationId, fcm_token_id: tokenId,
        push_status: "PENDING" }).select("id").single();
    if (error || !data) throw new Error("Unable to record pending push delivery.");
    return data.id;
  }

  async submitted(deliveryId: string, providerMessageId: string): Promise<void> {
    const { error } = await supabaseAdmin.from("notification_deliveries")
      .update({ push_status: "SUBMITTED",
        provider_message_id: providerMessageId,
        attempted_at: new Date().toISOString() }).eq("id", deliveryId);
    if (error) throw new Error("Unable to record push submission.");
  }

  async failed(deliveryId: string, reason: string): Promise<void> {
    const { error } = await supabaseAdmin.from("notification_deliveries")
      .update({ push_status: "FAILED", failure_reason: reason,
        attempted_at: new Date().toISOString() }).eq("id", deliveryId);
    if (error) throw new Error("Unable to record push failure.");
  }

  async deactivateToken(tokenId: string, recipientId: string): Promise<void> {
    const { error } = await supabaseAdmin.from("fcm_tokens")
      .update({ is_active: false }).eq("id", tokenId)
      .eq("user_id", recipientId);
    if (error) throw new Error("Unable to deactivate invalid push token.");
  }
}
