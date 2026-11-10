import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import { parsePredictionRules } from "../prediction/prediction-context.js";
import type { AdministrationRepo, AuditFilters, BakeryUpdate } from
  "./administration.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const weekDays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
  "THURSDAY", "FRIDAY", "SATURDAY"];
const weather = ["CLEAR", "CLOUDY", "RAIN", "STORM", "OTHER"];
const ruleKeys = ["baseQuantities", "weekdayFactors", "monsoonMonths",
  "monsoonFactor", "otherSeasonFactor", "weatherFactors",
  "weatherFallbackFactor", "holidayFactor", "nonHolidayFactor",
  "calendarVerifiedThrough", "allowCalendarFallback"];
type Repo = Pick<AdministrationRepo, "bakery" | "systemSettings" |
  "activeCategoryIds" | "saveBakery" | "saveSystem" | "audit">;

function object(raw: unknown, keys: readonly string[], exact: boolean):
  Record<string, unknown> {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw) ||
      Object.keys(raw).some((key) => !keys.includes(key)) ||
      (exact && Object.keys(raw).length !== keys.length)) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid administration fields.");
  }
  return raw as Record<string, unknown>;
}
function text(value: unknown, max = 120): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > max) {
    throw new AppError(400, "VALIDATION_ERROR", "A nonblank text value is required.");
  }
  return value.trim();
}
function sameKeys(value: unknown, keys: string[]): boolean {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    Object.keys(value).every((key) => keys.includes(key));
}
function nextDate(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + 86_400_000)
    .toISOString().slice(0, 10);
}

export class AdministrationService {
  constructor(private readonly providedRepo?: Repo,
    private readonly transport: typeof fetch = fetch,
    private readonly mlUrl: string = process.env.ML_SERVICE_URL ??
      "http://127.0.0.1:8000",
    private readonly fcmConfigured: boolean =
      Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {}
  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (
      await import("./administration.repo.js")
    ).AdministrationRepo();
  }

  async settings() {
    const repo = await this.repo();
    const [bakery, systemSettings] = await Promise.all([
      repo.bakery(), repo.systemSettings(),
    ]);
    return { bakery, systemSettings };
  }

  async serviceStatus() {
    const repo = await this.repo();
    const [database, ml] = await Promise.all([
      repo.bakery().then(() => "REACHABLE" as const)
        .catch(() => "UNREACHABLE" as const),
      (async () => {
        try {
          const response = await this.transport(new URL("/health", this.mlUrl), {
            signal: AbortSignal.timeout(2500),
          });
          return response.ok ? "REACHABLE" as const :
            "UNREACHABLE" as const;
        } catch { return "UNREACHABLE" as const; }
      })(),
    ]);
    return { database, ml,
      fcm: this.fcmConfigured ? "CREDENTIAL_PATH_CONFIGURED" :
        "NOT_CONFIGURED",
      weatherAdapter: process.env.OPENWEATHER_API_KEY &&
        process.env.BAKERY_LATITUDE && process.env.BAKERY_LONGITUDE ?
        "CONFIGURED_UNVERIFIED" : "NOT_CONFIGURED",
      calendarAdapter: "MANUAL_VERIFIED_ENTRIES",
      note: "Configuration does not prove weather reachability, calendar completeness, push delivery or prediction accuracy." };
  }

  async saveBakery(actorUserId: string, raw: unknown) {
    const input = object(raw, ["name", "locationType", "opensAt",
      "closesAt", "timezone"], true);
    const name = text(input.name);
    const locationType = text(input.locationType);
    const opensAt = text(input.opensAt, 5);
    const closesAt = text(input.closesAt, 5);
    const timezone = text(input.timezone, 80);
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(opensAt) ||
        !/^([01]\d|2[0-3]):[0-5]\d$/.test(closesAt) ||
        opensAt >= closesAt) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid bakery opening hours.");
    }
    try { new Intl.DateTimeFormat("en-US", { timeZone: timezone }); }
    catch { throw new AppError(400, "VALIDATION_ERROR", "Invalid bakery timezone."); }
    const update: BakeryUpdate = { name, locationType, opensAt,
      closesAt, timezone };
    return (await this.repo()).saveBakery(actorUserId, update);
  }

  async saveSystem(actorUserId: string, key: string, raw: unknown) {
    const input = object(raw, ["value"], true);
    let value = input.value;
    if (key === "prediction.low_confidence_threshold") {
      if (typeof value !== "number" || !Number.isFinite(value) ||
          value < 0 || value > 100) {
        throw new AppError(400, "VALIDATION_ERROR",
          "Confidence threshold must be from 0 to 100.");
      }
    } else if (key === "prediction.context_rules") {
      if (!sameKeys(value, ruleKeys)) throw new AppError(400,
        "VALIDATION_ERROR", "Prediction context fields are incomplete.");
      const rules = value as Record<string, unknown>;
      if (!sameKeys(rules.weekdayFactors, weekDays) ||
          !sameKeys(rules.weatherFactors, weather) ||
          typeof rules.baseQuantities !== "object" ||
          rules.baseQuantities === null || Array.isArray(rules.baseQuantities) ||
          Object.keys(rules.baseQuantities).some((id) => !uuid.test(id))) {
        throw new AppError(400, "VALIDATION_ERROR",
          "Prediction category/factor keys are invalid.");
      }
      try { parsePredictionRules(value); }
      catch { throw new AppError(400, "VALIDATION_ERROR",
        "Prediction context values are invalid."); }
      const active = await (await this.repo()).activeCategoryIds();
      const bases = rules.baseQuantities as Record<string, unknown>;
      if (active.some((id) => bases[id] === undefined)) {
        throw new AppError(400, "VALIDATION_ERROR",
          "Every active category needs a configured base quantity.");
      }
    } else {
      throw new AppError(400, "SETTING_NOT_EDITABLE",
        "This setting is not in the approved allowlist.");
    }
    return (await this.repo()).saveSystem(actorUserId, key, value);
  }

  async audit(raw: unknown) {
    const input = object(raw, ["from", "to", "eventType",
      "actorUserId", "outcome", "page"], false);
    const from = input.from === undefined ? null : input.from;
    const to = input.to === undefined ? null : input.to;
    const eventType = input.eventType === undefined ? null : input.eventType;
    const actorUserId = input.actorUserId === undefined ? null : input.actorUserId;
    const outcome = input.outcome === undefined ? null : input.outcome;
    const page = input.page === undefined ? 1 : Number(input.page);
    if (from !== null && (typeof from !== "string" || !isCalendarDate(from)) ||
        to !== null && (typeof to !== "string" || !isCalendarDate(to)) ||
        typeof from === "string" && typeof to === "string" && from > to ||
        eventType !== null &&
          (typeof eventType !== "string" || !/^[A-Z][A-Z0-9_]{0,79}$/.test(eventType)) ||
        actorUserId !== null &&
          (typeof actorUserId !== "string" || !uuid.test(actorUserId)) ||
        outcome !== null && outcome !== "SUCCESS" && outcome !== "FAILURE" ||
        input.page !== undefined &&
          (typeof input.page !== "string" || !/^[1-9]\d*$/.test(input.page)) ||
        !Number.isSafeInteger(page) || page < 1 || page > 42_949_672) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid audit filters.");
    }
    const filters: AuditFilters = {
      from: from === null ? null : `${from}T00:00:00Z`,
      toExclusive: to === null ? null : `${nextDate(to as string)}T00:00:00Z`,
      eventType: eventType as string | null,
      actorUserId: actorUserId as string | null,
      outcome: outcome as "SUCCESS" | "FAILURE" | null,
      page,
    };
    return (await this.repo()).audit(filters);
  }
}
