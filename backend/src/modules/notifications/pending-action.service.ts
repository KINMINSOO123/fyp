import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import type { PendingActionRepo, PendingSnapshot } from "./pending-action.repo.js";

export type PendingItem = {
  key: "NEXT_DAY_PREDICTION" | "PRODUCTION_CONFIRMATION" |
    "POS_SIMULATION" | "LEFTOVER_ALLOCATION";
  status: "READY" | "BLOCKED" | "COMPLETE";
  date: string;
  description: string;
  action: string | null;
};
type DataRepo = Pick<PendingActionRepo, "getBakeryTimezone" | "snapshot">;

function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function nextDate(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + 86_400_000)
    .toISOString().slice(0, 10);
}

export function derivePending(date: string, tomorrow: string,
  snapshot: PendingSnapshot, role: "BAKERY_MANAGER" | "SYSTEM_ADMINISTRATOR") {
  const active = new Set(snapshot.activeCategoryIds);
  const count = (ids: string[]) => new Set(ids.filter((id) => active.has(id))).size;
  const total = active.size;
  const todayPredictions = count(snapshot.todayPredictionIds);
  const nextPredictions = count(snapshot.nextPredictionIds);
  const confirmed = count(snapshot.confirmedCategoryIds);
  const completed = count(snapshot.completedCategoryIds);
  if (!Number.isSafeInteger(snapshot.remainingLeftovers) ||
      snapshot.remainingLeftovers < 0) throw new Error("Invalid pending balance.");
  const items: PendingItem[] = [];
  if (role === "BAKERY_MANAGER") {
    items.push({ key: "NEXT_DAY_PREDICTION", date: tomorrow,
      status: total > 0 && nextPredictions === total ? "COMPLETE" :
        total === 0 ? "BLOCKED" : "READY",
      description: `${nextPredictions}/${total} active categories predicted for tomorrow.`,
      action: total > 0 && nextPredictions < total ? "OPEN_PREDICTIONS" : null });
    items.push({ key: "PRODUCTION_CONFIRMATION", date,
      status: total > 0 && (confirmed === total || completed === total) ?
        "COMPLETE" : todayPredictions === total && total > 0 ?
          "READY" : "BLOCKED",
      description: `${confirmed}/${total} active categories confirmed for production.`,
      action: todayPredictions === total && confirmed < total ?
        "OPEN_PRODUCTION" : null });
    items.push({ key: "POS_SIMULATION", date,
      status: total > 0 && completed === total ? "COMPLETE" :
        total > 0 && confirmed === total && todayPredictions === total ?
          "READY" : "BLOCKED",
      description: `${completed}/${total} active categories have completed simulation.`,
      action: total > 0 && confirmed === total && completed < total ?
        "OPEN_SIMULATION" : null });
    items.push({ key: "LEFTOVER_ALLOCATION", date,
      status: completed === 0 ? "BLOCKED" :
        snapshot.remainingLeftovers > 0 ? "READY" : "COMPLETE",
      description: `${snapshot.remainingLeftovers} units remain unallocated.`,
      action: snapshot.remainingLeftovers > 0 ? "OPEN_LEFTOVERS" : null });
  }
  return { date, nextDate: tomorrow, role, activeCategories: total, items,
    administrationLinks: role === "SYSTEM_ADMINISTRATOR" ?
      ["OPEN_INVENTORY_ADMIN", "OPEN_MODEL_MANAGEMENT",
        "OPEN_USER_ADMIN"] : [] };
}

export class PendingActionService {
  constructor(private readonly providedRepo?: DataRepo,
    private readonly now: () => Date = () => new Date()) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./pending-action.repo.js")
    ).PendingActionRepo();
  }

  async get(role: "BAKERY_MANAGER" | "SYSTEM_ADMINISTRATOR", raw: unknown) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw) ||
        Object.keys(raw).some((key) => key !== "date")) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid pending-action filters.");
    }
    const query = raw as Record<string, unknown>;
    const repo = await this.repo();
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const date = query.date === undefined ? today : query.date;
    if (typeof date !== "string" || !isCalendarDate(date) || date > today) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid workflow date.");
    }
    const tomorrow = nextDate(date);
    return derivePending(date, tomorrow,
      await repo.snapshot(date, tomorrow), role);
  }
}
