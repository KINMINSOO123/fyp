import assert from "node:assert/strict";
import { test } from "node:test";
import type { Server } from "node:http";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { CalendarController } from "./calendar.controller.js";
import { CalendarService } from "./calendar.service.js";

test("T-DP-CAL-01 [FR-DP-04, FR-ADM-02]: calendar entry requires source and valid type", async () => {
  const saved: unknown[] = [];
  const service = new CalendarService({
    async list() { return []; },
    async add(actor, entry) { saved.push({ actor, entry }); return entry; },
  });
  const entry = { eventDate: "2026-11-11", eventType: "PUBLIC_HOLIDAY",
    eventName: " Verified event ", sourceReference: " official.example/reference " };
  const result = await service.add("admin", entry);
  assert.equal(result.eventName, "Verified event");
  assert.deepEqual(saved, [{ actor: "admin", entry: {
    ...entry, eventName: "Verified event",
    sourceReference: "official.example/reference",
  } }]);
  for (const invalid of [{ ...entry, sourceReference: " " },
    { ...entry, eventType: "UNKNOWN" },
    { ...entry, eventDate: "2026-02-30" },
    { ...entry, role: "SYSTEM_ADMINISTRATOR" }]) {
    await assert.rejects(service.add("admin", invalid),
      (error: unknown) => error instanceof AppError &&
        error.code === "VALIDATION_ERROR");
  }
  assert.equal(saved.length, 1);
});

test("T-DP-CAL-02 [BR-UAM-02, FR-ADM-02]: manager cannot enter or view administrator calendar", async () => {
  const controller = new CalendarController(new CalendarService({
    async list() { return []; },
    async add(_actor, entry) { return entry; },
  }));
  const app = express();
  app.use(express.json(), createAuthenticate({ async authenticate(token) {
    return { userId: token, fullName: "Test", accountStatus: "ACTIVE" as const,
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" as const :
        "BAKERY_MANAGER" as const };
  } }), requireRole("SYSTEM_ADMINISTRATOR"));
  app.get("/calendar", controller.list);
  app.post("/calendar", controller.add);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No port.");
    const base = `http://127.0.0.1:${address.port}/calendar`;
    for (const method of ["GET", "POST"]) {
      const denied = await fetch(`${base}?date=2026-11-11`, {
        method, headers: { Authorization: "Bearer manager",
          "Content-Type": "application/json" },
        ...(method === "POST" ? { body: JSON.stringify({}) } : {}),
      });
      assert.equal(denied.status, 403);
    }
    const allowed = await fetch(`${base}?date=2026-11-11`, {
      headers: { Authorization: "Bearer admin" },
    });
    assert.equal(allowed.status, 200);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});
