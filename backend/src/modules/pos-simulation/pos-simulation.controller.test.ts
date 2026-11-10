import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { PosSimulationController } from "./pos-simulation.controller.js";

test("T-POS-AUTO-04 [BR-UAM-02, FR-POS-01]: only active managers run; both roles read", async () => {
  let runs = 0;
  let reads = 0;
  const controller = new PosSimulationController({
    async getToday() { return { date: "2026-11-09" }; },
    async run(actorId) {
      assert.equal(actorId, "manager-id");
      runs++;
      return { date: "2026-11-09", operationId: "operation-1", items: [] };
    },
    async getResult() {
      reads++;
      return { date: "2026-11-09", operationId: null, items: [] };
    },
    async getTransactions() {
      reads++;
      return { date: "2026-11-09", page: 1,
        pageSize: 50, total: 0, items: [] };
    },
  });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (!["manager", "admin"].includes(token)) {
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    }
    return { userId: token === "manager" ? "manager-id" : "admin-id",
      fullName: "Test", role: token === "manager" ? "BAKERY_MANAGER" :
        "SYSTEM_ADMINISTRATOR", accountStatus: "ACTIVE" };
  } }));
  app.post("/api/simulations", requireRole("BAKERY_MANAGER"), controller.run);
  app.get("/api/simulations/:date", controller.getResult);
  app.get("/api/simulations/:date/transactions", controller.getTransactions);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}/api/simulations`;
    for (const token of [null, "admin", "manager"] as const) {
      const headers: Record<string, string> = token ?
        { Authorization: `Bearer ${token}` } : {};
      const response = await fetch(base, { method: "POST", headers });
      assert.equal(response.status, token === null ? 401 :
        token === "admin" ? 403 : 201);
    }
    assert.equal(runs, 1);
    for (const token of ["manager", "admin"]) {
      const response = await fetch(`${base}/2026-11-09`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(response.status, 200);
    }
    assert.equal(reads, 2);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
