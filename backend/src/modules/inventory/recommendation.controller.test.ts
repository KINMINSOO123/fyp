import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { RecommendationController } from "./recommendation.controller.js";

test("T-INV-AUTO-08 [BR-UAM-02, FR-INV-09]: only active managers read and confirm production plans", async () => {
  let reads = 0;
  let confirmedActor = "";
  const controller = new RecommendationController({
    async getPlan() { reads++; return { targetDate: "2026-11-05", status: "READY", entries: [],
      shortages: [], remainingPlanningBalance: [], outstandingCommitments: [] }; },
    async confirm(actorId) { confirmedActor = actorId; return { targetDate: "2026-11-05",
      status: "READY", entries: [], shortages: [], remainingPlanningBalance: [],
      outstandingCommitments: [] }; },
  });
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (token !== "manager" && token !== "admin") {
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    }
    return { userId: token === "manager" ? "manager-id" : "admin-id",
      fullName: "Test", role: token === "manager" ? "BAKERY_MANAGER" :
        "SYSTEM_ADMINISTRATOR", accountStatus: "ACTIVE" };
  } }), requireRole("BAKERY_MANAGER"));
  app.get("/api/recommendations/:date", controller.getPlan);
  app.put("/api/production-decisions", controller.confirm);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}`;
    for (const token of [null, "admin"] as const) {
      const headers: Record<string, string> = token ?
        { Authorization: `Bearer ${token}` } : {};
      const response = await fetch(`${base}/api/recommendations/2026-11-05`, { headers });
      assert.equal(response.status, token ? 403 : 401);
      const write = await fetch(`${base}/api/production-decisions`, {
        method: "PUT", headers,
      });
      assert.equal(write.status, token ? 403 : 401);
    }
    assert.equal(reads, 0);
    assert.equal(confirmedActor, "");
    const read = await fetch(`${base}/api/recommendations/2026-11-05`, {
      headers: { Authorization: "Bearer manager" },
    });
    assert.equal(read.status, 200);
    assert.equal(reads, 1);
    const write = await fetch(`${base}/api/production-decisions`, {
      method: "PUT", headers: { Authorization: "Bearer manager" },
    });
    assert.equal(write.status, 200);
    assert.equal(confirmedActor, "manager-id");
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
