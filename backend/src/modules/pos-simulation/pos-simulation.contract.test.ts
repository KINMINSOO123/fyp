import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { PosSimulationController } from "./pos-simulation.controller.js";
import { PosSimulationService } from "./pos-simulation.service.js";
import type { CurrentWeather } from "./current-weather.client.js";

test("T-POS-CONTRACT-01 [FR-POS-01, FR-POS-02]: Flutter date JSON reaches current-weather RPC boundary", async () => {
  const calls: Array<[string, string, CurrentWeather]> = [];
  const weather: CurrentWeather = { provider: "OPENWEATHER_CURRENT",
    condition: "RAIN", providerTimestamp: "2026-11-12T16:25:00.000Z",
    fetchedAt: "2026-11-12T16:30:00.000Z",
    location: { latitude: 3.203, longitude: 101.723 },
    requestedLocation: { latitude: 3.203, longitude: 101.723 } };
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete(actor, date, weather) {
      calls.push([actor, date, weather]);
      return { date, operationId: "operation-1", items: [] };
    },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-12T16:30:00Z"), {
    async get() { return weather; },
  });
  const controller = new PosSimulationController(service, {
    async publish() { return; },
  });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate() {
    return { userId: "manager", fullName: "Manager",
      role: "BAKERY_MANAGER", accountStatus: "ACTIVE" };
  } }));
  app.post("/api/simulations", requireRole("BAKERY_MANAGER"), controller.run);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const url = `http://127.0.0.1:${address.port}/api/simulations`;
    const send = async (body: unknown) => fetch(url, {
      method: "POST", headers: { Authorization: "Bearer test",
        "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    assert.equal((await send({ date: "2026-11-13" })).status, 201);
    assert.deepEqual(calls, [["manager", "2026-11-13", weather]]);
    for (const invalid of [
      { date: "2026-11-13T00:00:00Z" },
      { date: "2026-11-13", weatherCondition: "WET" },
      { date: "2026-11-13", weatherCondition: 1 },
      { date: "2026-11-13", predictedUnitsSold: 20 },
    ]) {
      const response = await send(invalid);
      assert.equal(response.status, 400);
      assert.equal((await response.json() as { error: { code: string } })
        .error.code, "VALIDATION_ERROR");
    }
    assert.equal(calls.length, 1);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
