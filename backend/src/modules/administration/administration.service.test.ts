import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { AdministrationController } from "./administration.controller.js";
import { AdministrationService } from "./administration.service.js";

const categoryId = "12345678-1234-4123-8123-123456789abc";
const bakery = { id: categoryId, name: "Smart Bakery",
  locationType: "Residential", opensAt: "06:00", closesAt: "18:00",
  timezone: "Asia/Kuala_Lumpur", updatedAt: "2026-11-09T00:00:00Z" };
const rules = { baseQuantities: { [categoryId]: 10 },
  weekdayFactors: { SUNDAY: 1, MONDAY: 1, TUESDAY: 1,
    WEDNESDAY: 1, THURSDAY: 1, FRIDAY: 1, SATURDAY: 1 },
  monsoonMonths: [], monsoonFactor: 1, otherSeasonFactor: 1,
  weatherFactors: { CLEAR: 1, CLOUDY: 1, RAIN: 1,
    STORM: 1, OTHER: 1 }, weatherFallbackFactor: 1,
  holidayFactor: 1, nonHolidayFactor: 1,
  calendarVerifiedThrough: null, allowCalendarFallback: true };

function fixture() {
  const calls: string[] = [];
  const repo = {
    async bakery() { return bakery; },
    async systemSettings() { return []; },
    async activeCategoryIds() { return [categoryId]; },
    async saveBakery(actor: string, input: { name: string }) {
      calls.push(`bakery:${actor}:${input.name}`);
      return { ...bakery, ...input };
    },
    async saveSystem(actor: string, key: string, value: unknown) {
      calls.push(`setting:${actor}:${key}`);
      return { key, value, dataType: key.endsWith("context_rules") ?
        "JSON" as const : "NUMERIC" as const,
        description: "Configured", updatedBy: actor,
        updatedAt: "2026-11-09T00:00:00Z" };
    },
    async audit(filters: { page: number; toExclusive: string | null }) {
      calls.push(`audit:${filters.page}:${filters.toExclusive}`);
      return { page: filters.page, pageSize: 50, total: 0, items: [] };
    },
  };
  return { calls, repo, service: new AdministrationService(repo) };
}

test("T-ADM-AUTO-01 [FR-ADM-01, FR-ADM-02]: validated allowlisted settings preserve actor", async () => {
  const { calls, service } = fixture();
  const validBakery = { name: " Bakery Two ", locationType: "Residential",
    opensAt: "06:00", closesAt: "18:00", timezone: "Asia/Kuala_Lumpur" };
  await service.saveBakery("admin", validBakery);
  await service.saveSystem("admin", "prediction.low_confidence_threshold",
    { value: 75 });
  await service.saveSystem("admin", "prediction.context_rules", { value: rules });
  assert.deepEqual(calls, [
    "bakery:admin:Bakery Two",
    "setting:admin:prediction.low_confidence_threshold",
    "setting:admin:prediction.context_rules",
  ]);
  await assert.rejects(service.saveBakery("admin", {
    ...validBakery, timezone: "Invalid/Zone" }));
  await assert.rejects(service.saveBakery("admin", {
    ...validBakery, opensAt: "19:00" }));
  await assert.rejects(service.saveSystem("admin",
    "prediction.low_confidence_threshold", { value: 101 }));
  await assert.rejects(service.saveSystem("admin", "provider.secret",
    { value: "secret" }));
  await assert.rejects(service.saveSystem("admin", "prediction.context_rules",
    { value: { ...rules, password: "secret" } }));
  await assert.rejects(service.saveSystem("admin", "prediction.context_rules",
    { value: { ...rules, baseQuantities: {} } }));
  assert.equal(calls.length, 3);
});

test("T-ADM-AUTO-02 [FR-ADM-04]: audit filters validate and use 50-row pages", async () => {
  const { calls, service } = fixture();
  const result = await service.audit({ from: "2026-11-01",
    to: "2026-11-09", page: "2", outcome: "SUCCESS" });
  assert.equal(result.pageSize, 50);
  assert.deepEqual(calls, ["audit:2:2026-11-10T00:00:00Z"]);
  await assert.rejects(service.audit({ actorUserId: "someone-else" }));
  await assert.rejects(service.audit({ role: "SYSTEM_ADMINISTRATOR" }));
  await assert.rejects(service.audit({ from: "2026-11-10", to: "2026-11-09" }));
  assert.equal(calls.length, 1);
});

test("T-ADM-AUTO-03 [BR-UAM-02, FR-ADM-01, FR-ADM-04]: manager cannot view or update administration", async () => {
  const { service } = fixture();
  const controller = new AdministrationController(service);
  const app = express();
  app.use(express.json());
  app.use(createAuthenticate({ async authenticate(token) {
    if (token !== "manager" && token !== "admin") {
      throw new AppError(401, "INVALID_TOKEN", "Invalid token.");
    }
    return { userId: token, fullName: "Test", accountStatus: "ACTIVE" as const,
      role: token === "admin" ? "SYSTEM_ADMINISTRATOR" as const :
        "BAKERY_MANAGER" as const };
  } }), requireRole("SYSTEM_ADMINISTRATOR"));
  app.get("/settings", controller.settings);
  app.patch("/settings/bakery", controller.saveBakery);
  app.get("/audit", controller.audit);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No port.");
    const base = `http://127.0.0.1:${address.port}`;
    for (const path of ["/settings", "/audit"]) {
      const denied = await fetch(`${base}${path}`, {
        headers: { Authorization: "Bearer manager" },
      });
      assert.equal(denied.status, 403);
      const response = await denied.json() as { error: { code: string } };
      assert.equal(response.error.code, "FORBIDDEN");
    }
    const deniedWrite = await fetch(`${base}/settings/bakery`, {
      method: "PATCH", headers: { Authorization: "Bearer manager",
        "Content-Type": "application/json" },
      body: JSON.stringify(bakery),
    });
    assert.equal(deniedWrite.status, 403);
    const allowed = await fetch(`${base}/settings`, {
      headers: { Authorization: "Bearer admin" },
    });
    assert.equal(allowed.status, 200);
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) =>
      error ? reject(error) : resolve()));
  }
});

test("T-ADM-AUTO-04 [FR-ADM-03]: service status exposes state, not provider credentials", async () => {
  const { repo } = fixture();
  const service = new AdministrationService(repo,
    async () => new Response("{}", { status: 200 }),
    "http://127.0.0.1:8000", true);
  const status = await service.serviceStatus();
  assert.equal(status.database, "REACHABLE");
  assert.equal(status.ml, "REACHABLE");
  assert.equal(status.fcm, "CREDENTIAL_PATH_CONFIGURED");
  assert.ok(["NOT_CONFIGURED", "CONFIGURED_UNVERIFIED"]
    .includes(status.weatherAdapter));
  assert.equal(status.calendarAdapter, "MANUAL_VERIFIED_ENTRIES");
  assert.ok(!JSON.stringify(status).includes("PRIVATE_KEY"));
  const invalidUrl = new AdministrationService(repo,
    async () => { throw new Error("should not reach transport"); },
    "invalid-url", false);
  assert.equal((await invalidUrl.serviceStatus()).ml, "UNREACHABLE");
});
