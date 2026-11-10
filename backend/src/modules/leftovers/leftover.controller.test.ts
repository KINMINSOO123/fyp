import assert from "node:assert/strict";
import type { Server } from "node:http";
import { test } from "node:test";
import express from "express";
import { createAuthenticate } from "../../middleware/authenticate.js";
import { errorHandler } from "../../middleware/errorHandler.js";
import { requireRole } from "../../middleware/requireRole.js";
import { AppError } from "../../shared/AppError.js";
import { CharityPartnerController, LeftoverManagementController } from
  "./leftover.controller.js";

test("T-LEFT-AUTO-05 [FR-LDW-03, FR-LDW-07]: manager allocates; administrator maintains charities; both review", async () => {
  let donations = 0;
  let charityCreates = 0;
  let reads = 0;
  const leftovers = new LeftoverManagementController({
    async list() { reads++; return { date: "2026-11-09", items: [] }; },
    async recommendation() { return { dailyResultId: "result-id",
      remainingUnallocated: 0, activeCharities: [],
      recommendation: "NO_LEFTOVER", automaticAllocation: false }; },
    async listCharities() { return []; },
    async donate() { donations++; return {}; },
    async recordWaste() { return {}; },
    async advanceDonation() { return {}; },
    async listDonations() { return { date: "2026-11-09", page: 1,
      pageSize: 50, total: 0, items: [] }; },
  });
  const charities = new CharityPartnerController({
    async list() { return []; },
    async save() { charityCreates++; return { id: "charity-id" }; },
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
  app.get("/api/leftovers", leftovers.list);
  app.post("/api/donations", requireRole("BAKERY_MANAGER"), leftovers.donate);
  app.post("/api/admin/charity-partners",
    requireRole("SYSTEM_ADMINISTRATOR"), charities.create);
  app.use(errorHandler);
  const server = await new Promise<Server>((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("No test port.");
    const base = `http://127.0.0.1:${address.port}/api`;
    for (const token of ["manager", "admin"]) {
      const headers = { Authorization: `Bearer ${token}` };
      assert.equal((await fetch(`${base}/leftovers`, { headers })).status, 200);
      assert.equal((await fetch(`${base}/donations`, {
        method: "POST", headers })).status, token === "manager" ? 201 : 403);
      assert.equal((await fetch(`${base}/admin/charity-partners`, {
        method: "POST", headers })).status, token === "admin" ? 201 : 403);
    }
    assert.equal(reads, 2);
    assert.equal(donations, 1);
    assert.equal(charityCreates, 1);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()));
  }
});
