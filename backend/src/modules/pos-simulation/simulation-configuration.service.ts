import { AppError } from "../../shared/AppError.js";
import type { SimulationConfigurationRepo } from
  "./simulation-configuration.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
  "THURSDAY", "FRIDAY", "SATURDAY"];
const weather = ["NEUTRAL", "CLEAR", "CLOUDY", "RAIN", "STORM", "OTHER"];
type Repo = Pick<SimulationConfigurationRepo,
  "get" | "saveBaseline" | "saveScenario">;

function exactObject(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== keys.length ||
      Object.keys(value).some((key) => !keys.includes(key))) {
    throw new AppError(400, "VALIDATION_ERROR",
      "Simulation settings fields are incomplete or unknown.");
  }
  return value as Record<string, unknown>;
}
function factor(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) &&
    value >= 0 && value <= 3 &&
    Math.abs(value * 10_000 - Math.round(value * 10_000)) < 1e-7;
}

export class SimulationConfigurationService {
  constructor(private readonly providedRepo?: Repo) {}
  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import(
      "./simulation-configuration.repo.js")).SimulationConfigurationRepo();
  }
  async get() { return (await this.repo()).get(); }

  async saveBaseline(actor: string, categoryId: string, raw: unknown) {
    if (!uuid.test(categoryId)) throw new AppError(400, "VALIDATION_ERROR",
      "A valid category is required.");
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new AppError(400, "VALIDATION_ERROR", "Choose a baseline source.");
    }
    const input = raw as Record<string, unknown>;
    if (input.source === "MANUAL") {
      exactObject(input, ["source", "baseDemand"]);
      if (typeof input.baseDemand !== "number" ||
          !Number.isFinite(input.baseDemand) || input.baseDemand < 0 ||
          input.baseDemand > 1_000_000 ||
          Math.round(input.baseDemand * 1000) / 1000 !== input.baseDemand) {
        throw new AppError(400, "VALIDATION_ERROR",
          "Manual base demand must be 0..1000000 with at most three decimals.");
      }
      return (await this.repo()).saveBaseline(actor, categoryId,
        "MANUAL", input.baseDemand);
    }
    exactObject(input, ["source"]);
    if (input.source !== "IMPORTED_HISTORICAL_AVERAGE") {
      throw new AppError(400, "VALIDATION_ERROR",
        "Choose manual or validated imported history.");
    }
    return (await this.repo()).saveBaseline(actor, categoryId,
      "IMPORTED_HISTORICAL_AVERAGE", null);
  }

  async saveScenario(actor: string, raw: unknown) {
    const input = exactObject(raw, ["weekdayFactors", "weatherFactors",
      "holidayFactor", "nonHolidayFactor", "variationMaxPct"]);
    const weekdayFactors = exactObject(input.weekdayFactors, weekdays);
    const weatherFactors = exactObject(input.weatherFactors, weather);
    if (Object.values(weekdayFactors).some((value) => !factor(value)) ||
        Object.values(weatherFactors).some((value) => !factor(value)) ||
        !factor(input.holidayFactor) || !factor(input.nonHolidayFactor) ||
        typeof input.variationMaxPct !== "number" ||
        !Number.isFinite(input.variationMaxPct) ||
        input.variationMaxPct < 0 || input.variationMaxPct > 30 ||
        Math.abs(input.variationMaxPct * 100 -
          Math.round(input.variationMaxPct * 100)) >= 1e-7) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Scenario factors must be 0..3 with four decimals; variation must be 0..30% with two decimals.");
    }
    return (await this.repo()).saveScenario(actor, {
      weekdayFactors: weekdayFactors as Record<string, number>,
      weatherFactors: weatherFactors as Record<string, number>,
      holidayFactor: input.holidayFactor,
      nonHolidayFactor: input.nonHolidayFactor,
      variationMaxPct: input.variationMaxPct,
    });
  }
}
