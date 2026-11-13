import { AppError } from "../../shared/AppError.js";
import { supabaseAdmin } from "../../config/supabase.js";
import type { MalaysiaHolidayYear } from "./malaysia-holiday.client.js";

export type KlHolidayCoverage = { year: number; lastSuccessfulAt: string;
  refreshAfter: string; sourceUrl: string; eventCount: number } | null;

export class KlHolidayRepo {
  async coverage(year: number): Promise<KlHolidayCoverage> {
    const { data, error } = await supabaseAdmin.from("kl_holiday_syncs")
      .select("holiday_year,last_successful_at,refresh_after,provider_source_reference,published_event_count")
      .eq("holiday_year", year).maybeSingle();
    if (error) {
      if (["42P01", "42703", "PGRST205"].includes(error.code)) throw new AppError(503,
        "KL_HOLIDAY_SCHEMA_NOT_READY", "Apply the KL holiday migration.");
      throw new Error("Unable to load KL holiday coverage.");
    }
    return data ? { year, lastSuccessfulAt: data.last_successful_at,
      refreshAfter: data.refresh_after,
      sourceUrl: data.provider_source_reference,
      eventCount: data.published_event_count } : null;
  }
  async events(year: number) {
    const { data, error } = await supabaseAdmin.from("calendar_events")
      .select("id,event_date,event_name,provider_source_reference,subject_to_change")
      .eq("provider", "MALAYSIA_HOLIDAY_API").eq("state_code", "KUL")
      .eq("is_current", true).gte("event_date", `${year}-01-01`)
      .lte("event_date", `${year}-12-31`).order("event_date");
    if (error || !data) throw new AppError(503, "CALENDAR_CONTEXT_UNAVAILABLE",
      "Unable to load KL holidays. Retry or check the KL holiday migration.");
    return data.map((row) => ({ id: row.id, eventDate: row.event_date,
      eventName: row.event_name, sourceReference: row.provider_source_reference,
      subjectToChange: row.subject_to_change }));
  }
  async save(actor: string, result: MalaysiaHolidayYear) {
    const { data, error } = await supabaseAdmin.rpc("sync_kl_public_holidays", {
      p_actor_user_id: actor, p_year: result.year,
      p_events: result.holidays.map((item) => ({ ...item })),
      p_source_reference: result.sourceUrl,
    });
    if (error) {
      if (["PGRST202", "PGRST205", "42883", "42P01", "42703"].includes(error.code)) {
        throw new AppError(503, "KL_HOLIDAY_SCHEMA_NOT_READY",
          "Apply the KL holiday migration.");
      }
      if (error.code === "42501") throw new AppError(403, "FORBIDDEN",
        "An active bakery role is required.");
      throw new AppError(503, "KL_HOLIDAY_SYNC_FAILED",
        "Unable to save KL holidays. Please retry refresh.");
    }
    return data;
  }
}
