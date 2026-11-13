import assert from "node:assert/strict";
import { test } from "node:test";
import { SimulationConfigurationService } from
  "./simulation-configuration.service.js";

const categoryId = "0338c346-a27f-44e9-ad05-7df9dce1904b";
const weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
  "THURSDAY", "FRIDAY", "SATURDAY"];
const weather = ["NEUTRAL", "CLEAR", "CLOUDY", "RAIN", "STORM", "OTHER"];
const emptyConfig = { categories: [], scenario: {
  scenarioVersion: 1, weekdayFactors: {}, weatherFactors: {},
  holidayFactor: 1, nonHolidayFactor: 1, variationMaxPct: 10,
  updatedAt: "2026-11-12T00:00:00Z",
} };

test("T-POS-CONFIG-01 [FR-POS-02]: administrator explicitly saves imported or manual baseline", async () => {
  const calls: unknown[][] = [];
  const service = new SimulationConfigurationService({
    async get() { return emptyConfig; },
    async saveBaseline(...args) { calls.push(args); return {}; },
    async saveScenario() { return {}; },
  });
  await service.saveBaseline("admin", categoryId,
    { source: "IMPORTED_HISTORICAL_AVERAGE" });
  await service.saveBaseline("admin", categoryId,
    { source: "MANUAL", baseDemand: 12.5 });
  assert.deepEqual(calls, [
    ["admin", categoryId, "IMPORTED_HISTORICAL_AVERAGE", null],
    ["admin", categoryId, "MANUAL", 12.5],
  ]);
  await assert.rejects(service.saveBaseline("admin", categoryId,
    { source: "MANUAL", baseDemand: 12, predictedUnitsSold: 20 }));
  await assert.rejects(service.saveBaseline("admin", categoryId,
    { source: "IMPORTED_HISTORICAL_AVERAGE", baseDemand: 12 }));
  assert.equal(calls.length, 2);
});

test("T-POS-CONFIG-02 [FR-POS-02]: scenario uses exact separate settings", async () => {
  let saved: unknown;
  const service = new SimulationConfigurationService({
    async get() { return emptyConfig; },
    async saveBaseline() { return {}; },
    async saveScenario(_actor, input) { saved = input; return {}; },
  });
  const scenario = {
    weekdayFactors: Object.fromEntries(weekdays.map((day) => [day, 1])),
    weatherFactors: Object.fromEntries(weather.map((item) => [item, 1])),
    holidayFactor: 1.05, nonHolidayFactor: 1, variationMaxPct: 10,
  };
  await service.saveScenario("admin", scenario);
  assert.deepEqual(saved, scenario);
  await assert.rejects(service.saveScenario("admin", {
    ...scenario, predictionContext: { weatherFactor: 0.95 },
  }));
  await assert.rejects(service.saveScenario("admin", {
    ...scenario, weatherFactors: { ...scenario.weatherFactors, RAIN: -1 },
  }));
});
