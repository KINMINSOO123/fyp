import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { RestockController } from "./restock.controller.js";

test("T-RST-05 [BR-UAM-02, EXT-RST-06]: manager requests and cancels; administrator reads only", async () => {
  const calls: string[] = [];
  const controller = new RestockController({
    async preview() { calls.push("preview"); return { targetDate: "2026-11-12",
      desiredQuantities: [], shortages: [] }; },
    async submit(actor) { calls.push(`submit:${actor}`); return {
      id: "00000000-0000-4000-8000-000000000001",
      productionDate: "2026-11-12", status: "PENDING" }; },
    async list(actor, role) { calls.push(`list:${actor}:${role}`); return []; },
    async cancel(actor) { calls.push(`cancel:${actor}`); return {
      id: "00000000-0000-4000-8000-000000000001", status: "CANCELLED" }; },
  }, { async publish() {} });
  const app = express();
  app.use(express.json(), createAuthenticate({ async authenticate(token) {
    return { userId: token, fullName: "Test", accountStatus: "ACTIVE" as const,
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" as const :
        "BAKERY_MANAGER" as const };
  } }));
  app.get("/restock/preview/:date", requireRole("BAKERY_MANAGER"),
    controller.preview);
  app.post("/restock", requireRole("BAKERY_MANAGER"), controller.submit);
  app.get("/admin/restock", requireRole("SYSTEM_ADMINISTRATOR"),
    controller.list);
  app.post("/restock/:requestId/cancel",
    requireRole("BAKERY_MANAGER"), controller.cancel);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No port.");
    const base = `http://127.0.0.1:${address.port}`;
    const request = (path: string, role: string, method = "GET") =>
      fetch(`${base}${path}`, { method,
        headers: { Authorization: `Bearer ${role}`,
          "Content-Type": "application/json" },
        ...(method === "POST" ? { body: "{}" } : {}) });
    assert.equal((await request("/restock/preview/2026-11-12",
      "manager")).status, 200);
    assert.equal((await request("/restock", "manager", "POST")).status, 201);
    assert.equal((await request("/admin/restock", "admin")).status, 200);
    assert.equal((await request("/restock/id/cancel",
      "manager", "POST")).status, 200);
    assert.equal((await request("/restock", "admin", "POST")).status, 403);
    assert.equal((await request("/restock/id/cancel", "admin", "POST")).status, 403);
    assert.equal((await request("/admin/restock", "manager")).status, 403);
    assert.deepEqual(calls, ["preview", "submit:manager",
      "list:admin:SYSTEM_ADMINISTRATOR", "cancel:manager"]);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
