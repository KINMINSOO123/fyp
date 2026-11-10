import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import type { CalendarEventType } from "./prediction-context.js";

export type CalendarEntry = { eventDate: string; eventType: CalendarEventType;
  eventName: string; sourceReference: string };

export class CalendarRepo {
  async list(date: string) {
    const { data, error } = await supabaseAdmin.from("calendar_events")
      .select("id,event_date,event_type,event_name,source_reference,fetched_at")
      .eq("event_date", date).order("event_name", { ascending: true });
    if (error || !data) throw new AppError(503, "CALENDAR_UNAVAILABLE",
      "Unable to load calendar events.");
    return data.map((row) => ({ id: row.id, eventDate: row.event_date,
      eventType: row.event_type, eventName: row.event_name,
      sourceReference: row.source_reference, recordedAt: row.fetched_at }));
  }

  async add(actorUserId: string, entry: CalendarEntry) {
    const { data, error } = await supabaseAdmin.rpc(
      "add_verified_calendar_event", {
        p_actor_user_id: actorUserId, p_event_date: entry.eventDate,
        p_event_type: entry.eventType, p_event_name: entry.eventName,
        p_source_reference: entry.sourceReference,
      });
    if (error?.code === "42501") throw new AppError(403, "FORBIDDEN",
      "Administrator permission is required.");
    if (error?.code === "23505" || error?.code === "P0001") {
      throw new AppError(409, "CALENDAR_EVENT_CONFLICT",
        "The event already exists or its prediction date is locked.");
    }
    if (error?.code === "PGRST202" || error?.code === "42883" ||
        error?.code === "42703") throw new AppError(503,
      "CALENDAR_SCHEMA_NOT_READY", "The calendar migration is not available.");
    if (error || !data) throw new AppError(503, "CALENDAR_UNAVAILABLE",
      "Unable to save the calendar event.");
    return data;
  }
}
