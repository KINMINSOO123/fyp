import assert from "node:assert/strict";
import { test } from "node:test";
import { PosSimulationService } from "./pos-simulation.service.js";
import type { CurrentWeather } from "./current-weather.client.js";

const date = "2026-11-09";
const actor = "manager-id";
const weather: CurrentWeather = {
  provider: "OPENWEATHER_CURRENT", condition: "RAIN",
  providerTimestamp: "2026-11-09T03:55:00.000Z",
  fetchedAt: "2026-11-09T04:00:00.000Z",
  location: { latitude: 3.203, longitude: 101.723 },
  requestedLocation: { latitude: 3.203, longitude: 101.723 },
};
const weatherClient = { async get() { return weather; } };

test("T-POS-AUTO-01 [FR-POS-01, FR-POS-02]: defaults to bakery-local date and delegates one official commit", async () => {
  const calls: Array<[string, string, CurrentWeather]> = [];
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete(userId, selectedDate, weather) {
      calls.push([userId, selectedDate, weather]);
      return { date: selectedDate, operationId: "operation-1", items: [] };
    },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-08T17:00:00Z"), weatherClient);
  const result = await service.run(actor, {});
  assert.equal(result.date, date);
  assert.deepEqual(calls, [[actor, date, weather]]);
  assert.deepEqual(await service.getToday(), { date });
});

test("T-POS-AUTO-02 [FR-POS-01, NFR-DAT-01]: rejects client quantities, actors, unknown fields and future date", async () => {
  let commits = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete() { commits++; return { date, operationId: "op", items: [] }; },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-09T04:00:00Z"), weatherClient);
  for (const body of [
    { date, producedOverride: 10 }, { date, actorUserId: "admin" },
    { date, feasibility: true },
    { date: "2026-02-30" }, { date, weatherCondition: "RAIN" }, null,
  ]) {
    await assert.rejects(service.run(actor, body),
      (error: unknown) => typeof error === "object" && error !== null &&
        "code" in error && error.code === "VALIDATION_ERROR");
  }
  assert.equal(commits, 0);
});

test("T-POS-AUTO-05 [FR-POS-02]: one resolved current observation reaches atomic demand generation", async () => {
  const calls: Array<[string, string, CurrentWeather]> = [];
  let fetches = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete(actorId, selectedDate, weather) {
      calls.push([actorId, selectedDate, weather]);
      return { date: selectedDate, operationId: "op", items: [] };
    },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-09T04:00:00Z"), { async get() {
    fetches++;
    return weather;
  } });
  await service.run(actor, { date });
  assert.deepEqual(calls, [[actor, date, weather]]);
  assert.equal(fetches, 1);
  await assert.rejects(service.run(actor, {
    date, predictedUnitsSold: 100,
  }));
  assert.equal(calls.length, 1);
  assert.equal(fetches, 1);
});

test("T-POS-WEATHER-01 [FR-POS-02]: historical date is rejected before weather lookup", async () => {
  let fetches = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete() { throw new Error("Unexpected commit."); },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-09T04:00:00Z"), { async get() {
    fetches++;
    return weather;
  } });
  await assert.rejects(service.run(actor, { date: "2026-11-08" }),
    (error: unknown) => typeof error === "object" && error !== null &&
      "code" in error && error.code === "CURRENT_WEATHER_TODAY_ONLY");
  assert.equal(fetches, 0);
});

test("T-POS-AUTO-03 [FR-POS-07, FR-POS-08]: transaction filters are constrained to 50 per page", async () => {
  let page = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete() { throw new Error("Not used."); },
    async getResult() { return { date, operationId: null, items: [] }; },
    async getTransactions(_date, input) {
      page = input.page;
      return { date, page, pageSize: 50, total: 0, items: [] };
    },
  });
  assert.equal((await service.getTransactions(date, { page: "2",
    timeSlot: "MORNING" })).pageSize, 50);
  assert.equal(page, 2);
  await assert.rejects(service.getTransactions(date, { page: "0" }));
  await assert.rejects(service.getTransactions(date, { timeSlot: "MIDNIGHT" }));
});
