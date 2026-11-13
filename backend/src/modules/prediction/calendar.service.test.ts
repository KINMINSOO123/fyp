import assert from "node:assert/strict";
import { test } from "node:test";
import type { Server } from "node:http";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { KlHolidayController } from "./kl-holiday.controller.js";

test("T-DP-CAL-01 [BR-UAM-02, FR-ADM-02]: only administrator can inspect and refresh KL holidays", async () => {
  const calls: string[] = [];
  const controller = new KlHolidayController({
    async list(year) { calls.push(`list:${year}`); return {
      year, stateCode: "KUL", status: "NOT_SYNCED", coverage: null, events: [] }; },
    async refresh(actor, year) { calls.push(`refresh:${actor}:${year}`);
      return { year, stateCode: "KUL", status: "NOT_SYNCED", coverage: null, events: [] }; },
  });
  const app = express();
  app.use(express.json(), createAuthenticate({ async authenticate(token) {
    return { userId: token, fullName: "Test", accountStatus: "ACTIVE" as const,
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" as const :
        "BAKERY_MANAGER" as const };
  } }), requireRole("SYSTEM_ADMINISTRATOR"));
  app.get("/calendar", controller.list);
  app.post("/calendar/refresh", controller.refresh);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No port.");
    const base = `http://127.0.0.1:${address.port}/calendar`;
    for (const method of ["GET", "POST"]) {
      const denied = await fetch(method === "GET" ? `${base}?year=2026` :
        `${base}/refresh`, { method,
        headers: { Authorization: "Bearer manager",
          "Content-Type": "application/json" },
        ...(method === "POST" ? { body: JSON.stringify({ year: 2026 }) } : {}),
      });
      assert.equal(denied.status, 403);
    }
    assert.equal(calls.length, 0);
    const allowed = await fetch(`${base}/refresh`, { method: "POST",
      headers: { Authorization: "Bearer admin",
        "Content-Type": "application/json" },
      body: JSON.stringify({ year: 2026 }) });
    assert.equal(allowed.status, 200);
    assert.deepEqual(calls, ["refresh:admin:2026"]);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
