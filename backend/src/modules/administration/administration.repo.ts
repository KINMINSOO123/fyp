import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export type BakerySettings = { id: string; name: string;
  locationType: string; opensAt: string; closesAt: string;
  timezone: string; updatedAt: string };
export type SystemSetting = { key: string; value: unknown;
  dataType: "NUMERIC" | "JSON"; description: string;
  updatedBy: string; updatedAt: string };
export type BakeryUpdate = Omit<BakerySettings, "id" | "updatedAt">;
export type AuditFilters = { from: string | null; toExclusive: string | null;
  eventType: string | null; actorUserId: string | null;
  outcome: "SUCCESS" | "FAILURE" | null; page: number };

export class AdministrationRepo {
  async bakery(): Promise<BakerySettings> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("id,name,location_type,opens_at,closes_at,timezone,updated_at")
      .eq("singleton_guard", true).single();
    if (error || !data) throw new AppError(503, "SETTINGS_UNAVAILABLE",
      "Unable to load bakery settings.");
    return { id: data.id, name: data.name,
      locationType: data.location_type,
      opensAt: String(data.opens_at).slice(0, 5),
      closesAt: String(data.closes_at).slice(0, 5),
      timezone: data.timezone, updatedAt: data.updated_at };
  }

  async systemSettings(): Promise<SystemSetting[]> {
    const { data, error } = await supabaseAdmin.from("system_settings")
      .select("setting_key,setting_value,data_type,description,updated_by,updated_at")
      .in("setting_key", ["prediction.low_confidence_threshold",
        "prediction.context_rules"])
      .order("setting_key", { ascending: true });
    if (error || !data) throw new AppError(503, "SETTINGS_UNAVAILABLE",
      "Unable to load system settings.");
    return data.map((row) => ({ key: row.setting_key,
      value: row.setting_value, dataType: row.data_type as "NUMERIC" | "JSON",
      description: row.description, updatedBy: row.updated_by,
      updatedAt: row.updated_at }));
  }

  async activeCategoryIds(): Promise<string[]> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id").eq("is_active", true);
    if (error || !data) throw new AppError(503, "SETTINGS_UNAVAILABLE",
      "Unable to load active bread categories.");
    return data.map((row) => row.id);
  }

  async saveBakery(actorUserId: string, input: BakeryUpdate):
    Promise<BakerySettings> {
    const { data, error } = await supabaseAdmin.rpc(
      "update_bakery_settings_with_audit", {
        p_actor_user_id: actorUserId, p_name: input.name,
        p_location_type: input.locationType,
        p_opens_at: input.opensAt, p_closes_at: input.closesAt,
        p_timezone: input.timezone,
      });
    if (error) throw settingError(error);
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error("Bakery settings update returned no result.");
    }
    return data as BakerySettings;
  }

  async saveSystem(actorUserId: string, key: string, value: unknown):
    Promise<SystemSetting> {
    const { data, error } = await supabaseAdmin.rpc(
      "update_admin_system_setting_with_audit", {
        p_actor_user_id: actorUserId,
        p_setting_key: key, p_setting_value: value,
      });
    if (error) throw settingError(error);
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error("System setting update returned no result.");
    }
    return data as SystemSetting;
  }

  async audit(filters: AuditFilters) {
    let query = supabaseAdmin.from("system_logs")
      .select("id,actor_user_id,event_type,entity_type,entity_id,outcome,severity,created_at",
        { count: "exact" });
    if (filters.from) query = query.gte("created_at", filters.from);
    if (filters.toExclusive) query = query.lt("created_at", filters.toExclusive);
    if (filters.eventType) query = query.eq("event_type", filters.eventType);
    if (filters.actorUserId) query = query.eq("actor_user_id", filters.actorUserId);
    if (filters.outcome) query = query.eq("outcome", filters.outcome);
    const { data, count, error } = await query
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range((filters.page - 1) * 50, filters.page * 50 - 1);
    if (error || !data || count === null) throw new AppError(503,
      "AUDIT_UNAVAILABLE", "Unable to load audit events.");
    return { page: filters.page, pageSize: 50, total: count,
      items: data.map((row) => ({ id: row.id,
        actorUserId: row.actor_user_id, eventType: row.event_type,
        entityType: row.entity_type, entityId: row.entity_id,
        outcome: row.outcome, severity: row.severity,
        createdAt: row.created_at })) };
  }
}

function settingError(error: { code?: string; message: string }): Error {
  if (error.code === "42501") return new AppError(403, "FORBIDDEN",
    "Administrator permission is required.");
  if (["22023", "23514", "23502", "22P02"].includes(error.code ?? "")) {
    return new AppError(409, "SETTINGS_CONFLICT", error.message);
  }
  if (error.code === "PGRST202" || error.code === "42883") {
    return new AppError(503, "SETTINGS_SCHEMA_NOT_READY",
      "Apply the audited settings migration first.");
  }
  return new Error("Unable to save settings.");
}
