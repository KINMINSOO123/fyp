import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "./history-selection.service.js";
import type { CalendarEntry, CalendarRepo } from "./calendar.repo.js";

type Repo = Pick<CalendarRepo, "list" | "add">;
const eventTypes = ["PUBLIC_HOLIDAY", "SCHOOL_HOLIDAY",
  "LOCAL_EVENT", "RELIGIOUS_HOLIDAY"];

export class CalendarService {
  constructor(private readonly providedRepo?: Repo) {}
  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import(
      "./calendar.repo.js")).CalendarRepo();
  }
  async list(date: string) {
    if (!isCalendarDate(date)) throw new AppError(400, "VALIDATION_ERROR",
      "A valid calendar date is required.");
    return (await this.repo()).list(date);
  }
  async add(actorUserId: string, raw: unknown) {
    const input = raw as Record<string, unknown> | null;
    if (!input || typeof input !== "object" || Array.isArray(input) ||
        Object.keys(input).length !== 4 ||
        Object.keys(input).some((key) => ![
          "eventDate", "eventType", "eventName", "sourceReference",
        ].includes(key)) ||
        typeof input.eventDate !== "string" ||
        !isCalendarDate(input.eventDate) ||
        !eventTypes.includes(String(input.eventType)) ||
        typeof input.eventName !== "string" ||
        !input.eventName.trim() || input.eventName.length > 120 ||
        typeof input.sourceReference !== "string" ||
        !input.sourceReference.trim() || input.sourceReference.length > 500) {
      throw new AppError(400, "VALIDATION_ERROR",
        "A date, event type, name and verifiable source reference are required.");
    }
    const entry: CalendarEntry = {
      eventDate: input.eventDate,
      eventType: input.eventType as CalendarEntry["eventType"],
      eventName: input.eventName.trim(),
      sourceReference: input.sourceReference.trim(),
    };
    return (await this.repo()).add(actorUserId, entry);
  }
}
