import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import type { PosSimulationRepo } from "./pos-simulation.repo.js";
import { CurrentWeatherClient } from "./current-weather.client.js";
import type { CurrentWeather } from "./current-weather.client.js";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type DataRepo = Pick<PosSimulationRepo,
  "getBakeryTimezone" | "complete" | "getResult" | "getTransactions">;

function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export class PosSimulationService {
  constructor(private readonly providedRepo?: DataRepo,
    private readonly now: () => Date = () => new Date(),
    private readonly weather: Pick<CurrentWeatherClient, "get"> =
      new CurrentWeatherClient()) {}

  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./pos-simulation.repo.js")
    ).PosSimulationRepo();
  }

  async getToday() {
    return { date: bakeryDate(this.now(), await (await this.repo()).getBakeryTimezone()) };
  }

  async run(actorUserId: string, body: unknown) {
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new AppError(400, "VALIDATION_ERROR", "A simulation request is required.");
    }
    const request = body as Record<string, unknown>;
    if (Object.keys(request).some((key) => key !== "date") ||
        (request.date !== undefined &&
         (typeof request.date !== "string" || !isCalendarDate(request.date)))) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Only an optional valid date is accepted.");
    }
    const repo = await this.repo();
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const date = typeof request.date === "string" ? request.date : today;
    if (date !== today) {
      throw new AppError(409, "CURRENT_WEATHER_TODAY_ONLY",
        "Current-weather simulation can run only for today's bakery date. Past and future dates need a separately labelled scenario.");
    }
    // Resolve one observation before entering the atomic database operation.
    const resolvedWeather: CurrentWeather = await this.weather.get();
    if (bakeryDate(this.now(), await repo.getBakeryTimezone()) !== date) {
      throw new AppError(409, "CURRENT_WEATHER_TODAY_ONLY",
        "The bakery date changed while fetching weather. Refresh and retry.");
    }
    return repo.complete(actorUserId, date, resolvedWeather);
  }

  async getResult(date: string) {
    if (!isCalendarDate(date)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid simulation date is required.");
    }
    return (await this.repo()).getResult(date);
  }

  async getTransactions(date: string, rawQuery: unknown) {
    if (!isCalendarDate(date) || typeof rawQuery !== "object" ||
        rawQuery === null || Array.isArray(rawQuery)) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid transaction request.");
    }
    const query = rawQuery as Record<string, unknown>;
    if (Object.keys(query).some((key) =>
      !["breadCategoryId", "timeSlot", "page"].includes(key)) ||
        (query.breadCategoryId !== undefined &&
         (typeof query.breadCategoryId !== "string" ||
          !uuidPattern.test(query.breadCategoryId))) ||
        (query.timeSlot !== undefined &&
         !["MORNING", "AFTERNOON", "EVENING"].includes(String(query.timeSlot))) ||
        (query.page !== undefined &&
         (typeof query.page !== "string" || !/^[1-9]\d*$/.test(query.page) ||
          !Number.isSafeInteger(Number(query.page)) || Number(query.page) > 42_949_672))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid transaction filters.");
    }
    return (await this.repo()).getTransactions(date, {
      breadCategoryId: query.breadCategoryId as string | undefined,
      timeSlot: query.timeSlot as string | undefined,
      page: query.page === undefined ? 1 : Number(query.page),
    });
  }
}
