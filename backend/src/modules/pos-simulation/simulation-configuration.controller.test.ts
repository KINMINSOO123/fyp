import assert from "node:assert/strict";
import { test } from "node:test";
import type { Server } from "node:http";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { requireRole } from "../../middleware/requireRole.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { AppError } from "../../shared/AppError.js";
import { SimulationConfigurationController } from
  "./simulation-configuration.controller.js";

test("T-POS-CONFIG-03 [BR-UAM-02, FR-POS-02]: only active administrators manage simulation settings", async () => {
  let reads = 0;
  let writes = 0;
  const controller = new SimulationConfigurationController({
    async get() { reads++; return { categories: [], scenario: {
      scenarioVersion: 1, weekdayFactors: {}, weatherFactors: {},
      holidayFactor: 1, nonHolidayFactor: 1, variationMaxPct: 10,
      updatedAt: "2026-11-12T00:00:00Z",
    } }; },
    async saveBaseline() { writes++; return {}; },
    async saveScenario() { writes++; return {}; },
  });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (token !== "admin" && token !== "manager") {
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    }
    return { userId: token, fullName: "Test",
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" : "BAKERY_MANAGER",
      accountStatus: "ACTIVE" };
  } }));
  app.get("/settings", requireRole("SYSTEM_ADMINISTRATOR"), controller.get);
  app.patch("/settings/scenario", requireRole("SYSTEM_ADMINISTRATOR"),
    controller.scenario);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No port.");
    const url = `http://127.0.0.1:${address.port}/settings`;
    for (const token of [null, "manager", "admin"] as const) {
      const headers: Record<string, string> = token ?
        { Authorization: `Bearer ${token}` } : {};
      const response = await fetch(url, { headers });
      assert.equal(response.status, token === null ? 401 :
        token === "manager" ? 403 : 200);
    }
    assert.equal(reads, 1);
    const response = await fetch(`${url}/scenario`, { method: "PATCH",
      headers: { Authorization: "Bearer manager" } });
    assert.equal(response.status, 403);
    assert.equal(writes, 0);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
