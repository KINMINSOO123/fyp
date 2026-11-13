import { createHash } from "node:crypto";
import type { SimulationItem } from "./pos-simulation.repo.js";

function fixed(value: unknown, decimals: number, field: string): bigint {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Invalid simulation ${field}.`);
  }
  const match = String(value).match(/^(\d+)(?:\.(\d+))?$/);
  if (!match || (match[2]?.length ?? 0) > decimals) {
    throw new Error(`Invalid simulation ${field} precision.`);
  }
  return BigInt(match[1]!) * 10n ** BigInt(decimals) +
    BigInt((match[2] ?? "").padEnd(decimals, "0") || "0");
}

function signedVariation(value: unknown): bigint {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      Math.abs(value) > 30) {
    throw new Error("Invalid simulation variation.");
  }
  const sign = value < 0 ? -1n : 1n;
  return sign * fixed(Math.abs(value), 2, "variation");
}

export function scenarioSeed(date: string, categoryId: string,
  version: number): string {
  if (!Number.isSafeInteger(version) || version < 1) {
    throw new Error("Invalid simulation scenario version.");
  }
  return createHash("md5").update(
    `${date}:${categoryId}:scenario:${version}`,
  ).digest("hex");
}

export function scenarioDemand(snapshot: Record<string, unknown>): number {
  const baseline = snapshot.baseline;
  if (!baseline || typeof baseline !== "object" || Array.isArray(baseline)) {
    throw new Error("Missing simulation baseline snapshot.");
  }
  const value = (baseline as Record<string, unknown>).value;
  const baseMilli = fixed(value, 3, "base demand");
  const weekday = fixed(snapshot.weekdayFactor, 4, "weekday factor");
  const holiday = fixed(snapshot.holidayFactor, 4, "holiday factor");
  const weather = fixed(snapshot.weatherFactor, 4, "weather factor");
  const variation = 10_000n + signedVariation(snapshot.variationPct);
  const numerator = baseMilli * weekday * holiday * weather * variation;
  const denominator = 1000n * 10_000n ** 4n;
  const rounded = (numerator + denominator / 2n) / denominator;
  if (rounded > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error("Simulation demand is too large.");
  }
  return Number(rounded);
}

export function validateSimulationItem(item: SimulationItem,
  date: string): void {
  if (!Number.isSafeInteger(item.produced) || item.produced < 0 ||
      !Number.isSafeInteger(item.simulatedDemand) ||
      item.simulatedDemand < 0 ||
      !Number.isSafeInteger(item.unitsSold) ||
      !Number.isSafeInteger(item.lostSales) ||
      !Number.isSafeInteger(item.leftover) ||
      item.unitsSold !== Math.min(item.simulatedDemand, item.produced) ||
      item.lostSales !== Math.max(0, item.simulatedDemand - item.produced) ||
      item.leftover !== item.produced - item.unitsSold ||
      item.estimatedDemand !== item.simulatedDemand ||
      item.salesPredictionError !==
        item.unitsSold - item.predictedUnitsSold) {
    throw new Error("Simulation sales do not reconcile.");
  }
  if (item.simulationMethod === "PREDICTION_SCALED_V1") {
    if (item.simulationSnapshot !== null) {
      throw new Error("Legacy simulation has an unexpected snapshot.");
    }
    return;
  }
  if (!["INDEPENDENT_BASELINE_V2", "INDEPENDENT_CURRENT_WEATHER_V3"]
    .includes(item.simulationMethod) ||
      !item.simulationSnapshot) {
    throw new Error("Invalid simulation method or snapshot.");
  }
  const snapshot = item.simulationSnapshot;
  if (snapshot.method !== item.simulationMethod ||
      snapshot.generatedDemand !== item.simulatedDemand ||
      snapshot.seed !== scenarioSeed(date, item.breadCategoryId,
        snapshot.scenarioVersion as number) ||
      scenarioDemand(snapshot) !== item.simulatedDemand) {
    throw new Error("Independent simulation snapshot does not reconcile.");
  }
  if (item.simulationMethod === "INDEPENDENT_CURRENT_WEATHER_V3") {
    const weather = snapshot.currentWeather as Record<string, unknown> | undefined;
    if (!weather || weather.provider !== "OPENWEATHER_CURRENT" ||
        weather.condition !== snapshot.weatherCondition ||
        typeof weather.providerTimestamp !== "string" ||
        !Number.isFinite(Date.parse(weather.providerTimestamp)) ||
        typeof weather.fetchedAt !== "string" ||
        !Number.isFinite(Date.parse(weather.fetchedAt)) ||
        typeof weather.location !== "object" || weather.location === null ||
        typeof weather.requestedLocation !== "object" ||
        weather.requestedLocation === null) {
      throw new Error("Current weather snapshot is incomplete.");
    }
  }
}
