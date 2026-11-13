import assert from "node:assert/strict";
import { test } from "node:test";
import type { SimulationItem } from "./pos-simulation.repo.js";
import { scenarioDemand, scenarioSeed, validateSimulationItem } from
  "./simulation-result-validation.js";

const date = "2026-11-12";
const categoryId = "0338c346-a27f-44e9-ad05-7df9dce1904b";
const snapshot: Record<string, unknown> = {
  method: "INDEPENDENT_BASELINE_V2",
  baseline: { value: 20, source: "MANUAL" },
  scenarioVersion: 1, weekdayFactor: 1, holidayFactor: 1,
  weatherFactor: 1, variationPct: 0,
  seed: scenarioSeed(date, categoryId, 1), generatedDemand: 20,
};

function item(predicted: number, produced: number): SimulationItem {
  const demand = 20;
  const sold = Math.min(demand, produced);
  return {
    breadCategoryId: categoryId, breadCategoryName: "Wholemeal Bread",
    predictionId: "prediction", productionDecisionId: "decision",
    dailyProductionId: "production", dailyResultId: "result",
    predictedUnitsSold: predicted, simulatedDemand: demand,
    simulationMethod: "INDEPENDENT_BASELINE_V2",
    simulationSnapshot: snapshot,
    predictionMode: "COLD_START", confidence: null, modelVersionId: null,
    produced, unitsSold: sold, lostSales: Math.max(0, demand - produced),
    estimatedDemand: demand, leftover: produced - sold,
    remainingUnallocatedLeftover: produced - sold,
    salesPredictionError: sold - predicted, leftoverRatePct: null,
    revenue: 0, ingredientCost: 0, grossProfit: 0,
    dataOrigin: "SIMULATION_GENERATED",
  };
}

test("T-POS-DEMAND-01 [FR-POS-02]: prediction changes comparison, not generated demand", () => {
  const first = item(15, 18);
  const second = item(100, 18);
  validateSimulationItem(first, date);
  validateSimulationItem(second, date);
  assert.equal(first.simulatedDemand, second.simulatedDemand);
  assert.notEqual(first.salesPredictionError, second.salesPredictionError);
});

test("T-POS-DEMAND-02 [BR-POS-02–06]: production changes fulfilment, not generated demand", () => {
  const lowProduction = item(15, 18);
  const highProduction = item(15, 25);
  validateSimulationItem(lowProduction, date);
  validateSimulationItem(highProduction, date);
  assert.equal(lowProduction.simulatedDemand, highProduction.simulatedDemand);
  assert.deepEqual([lowProduction.unitsSold, lowProduction.lostSales,
    lowProduction.leftover], [18, 2, 0]);
  assert.deepEqual([highProduction.unitsSold, highProduction.lostSales,
    highProduction.leftover], [20, 0, 5]);
});

test("T-POS-DEMAND-03 [FR-POS-02]: same scenario seed and factors reproduce demand", () => {
  assert.equal(scenarioSeed(date, categoryId, 1),
    scenarioSeed(date, categoryId, 1));
  assert.notEqual(scenarioSeed(date, categoryId, 1),
    scenarioSeed(date, categoryId, 2));
  assert.equal(scenarioDemand(snapshot), scenarioDemand({ ...snapshot }));
  assert.equal(scenarioDemand({ ...snapshot, baseline: {
    value: 10.5, source: "MANUAL" }, variationPct: 0 }), 11);
  assert.throws(() => validateSimulationItem({ ...item(15, 18),
    simulatedDemand: 19 }, date), /reconcile/);
});

test("T-POS-WEATHER-04 [FR-POS-02]: V3 snapshot keeps observation separate from demand arithmetic", () => {
  const currentWeather = {
    provider: "OPENWEATHER_CURRENT", condition: "RAIN",
    providerTimestamp: "2026-11-12T03:55:00.000Z",
    fetchedAt: "2026-11-12T04:00:00.000Z",
    location: { latitude: 3.203, longitude: 101.723 },
    requestedLocation: { latitude: 3.203, longitude: 101.723 },
  };
  const v3 = { ...item(15, 18),
    simulationMethod: "INDEPENDENT_CURRENT_WEATHER_V3" as const,
    simulationSnapshot: { ...snapshot,
      method: "INDEPENDENT_CURRENT_WEATHER_V3",
      weatherCondition: "RAIN", currentWeather } };
  validateSimulationItem(v3, date);
  assert.equal(scenarioDemand(v3.simulationSnapshot), 20);
  assert.throws(() => validateSimulationItem({ ...v3,
    simulationSnapshot: { ...v3.simulationSnapshot,
      currentWeather: { ...currentWeather, provider: "FORECAST" } } }, date),
  /weather snapshot/);
});
