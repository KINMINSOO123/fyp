import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { PredictionController } from "./prediction.controller.js";

test("T-DP-GEN-04 [BR-UAM-02, FR-DP-05]: manager generates; both roles read stored predictions", async () => {
  let generationActor = "";
  const controller = new PredictionController({
    async generate(actorId) {
      generationActor = actorId;
      return { targetDate: "2026-11-05", predictions: [] };
    },
    async listByDate() { return []; },
    async getNextDayState() { return {
      targetDate: "2026-11-05", predictions: [],
    }; },
  });
  const app = express();
  app.use(express.json());
  const authenticate = createAuthenticate({
    async authenticate(token) {
      if (token !== "manager" && token !== "administrator") {
        throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
      }
      return { userId: token === "manager" ? "manager-id" : "admin-id",
        fullName: "Test user",
        role: token === "manager" ? "BAKERY_MANAGER" : "SYSTEM_ADMINISTRATOR",
        accountStatus: "ACTIVE" };
    },
  });
  app.post("/api/predictions", authenticate,
    requireRole("BAKERY_MANAGER"), controller.generate);
  app.get("/api/predictions/next", authenticate, controller.nextDay);
  app.get("/api/predictions/:date", authenticate, controller.listByDate);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}/api/predictions`;
    const denied = await fetch(base, {
      method: "POST", headers: { Authorization: "Bearer administrator" },
    });
    assert.equal(denied.status, 403);
    assert.equal(generationActor, "");
    const created = await fetch(base, {
      method: "POST", headers: { Authorization: "Bearer manager",
        "Content-Type": "application/json" }, body: "{}",
    });
    assert.equal(created.status, 201);
    assert.equal(generationActor, "manager-id");
    for (const token of ["manager", "administrator"]) {
      const read = await fetch(`${base}/2026-11-05`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(read.status, 200);
    }
    const next = await fetch(`${base}/next`, {
      headers: { Authorization: "Bearer manager" },
    });
    assert.equal(next.status, 200);
    assert.equal((await next.json()).data.targetDate, "2026-11-05");
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
