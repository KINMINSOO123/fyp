import assert from "node:assert/strict";
import { test } from "node:test";
import { PosSimulationService } from "./pos-simulation.service.js";

const date = "2026-11-09";
const actor = "manager-id";

test("T-POS-AUTO-01 [FR-POS-01, FR-POS-02]: defaults to bakery-local date and delegates one official commit", async () => {
  const calls: Array<[string, string]> = [];
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete(userId, selectedDate) {
      calls.push([userId, selectedDate]);
      return { date: selectedDate, operationId: "operation-1", items: [] };
    },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-08T17:00:00Z"));
  const result = await service.run(actor, {});
  assert.equal(result.date, date);
  assert.deepEqual(calls, [[actor, date]]);
  assert.deepEqual(await service.getToday(), { date });
});

test("T-POS-AUTO-02 [FR-POS-01, NFR-DAT-01]: rejects client quantities, actors, unknown fields and future date", async () => {
  let commits = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete() { commits++; return { date, operationId: "op", items: [] }; },
    async getResult() { throw new Error("Not used."); },
    async getTransactions() { throw new Error("Not used."); },
  }, () => new Date("2026-11-09T04:00:00Z"));
  for (const body of [
    { date, producedOverride: 10 }, { date, actorUserId: "admin" },
    { date, feasibility: true }, { date: "2026-11-10" },
    { date: "2026-02-30" }, null,
  ]) {
    await assert.rejects(service.run(actor, body),
      (error: unknown) => typeof error === "object" && error !== null &&
        "code" in error && error.code === "VALIDATION_ERROR");
  }
  assert.equal(commits, 0);
});

test("T-POS-AUTO-03 [FR-POS-07, FR-POS-08]: transaction filters are constrained to 50 per page", async () => {
  let page = 0;
  const service = new PosSimulationService({
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async complete() { throw new Error("Not used."); },
    async getResult() { return { date, operationId: null, items: [] }; },
    async getTransactions(_date, input) {
      page = input.page;
      return { date, page, pageSize: 50, total: 0, items: [] };
    },
  });
  assert.equal((await service.getTransactions(date, { page: "2",
    timeSlot: "MORNING" })).pageSize, 50);
  assert.equal(page, 2);
  await assert.rejects(service.getTransactions(date, { page: "0" }));
  await assert.rejects(service.getTransactions(date, { timeSlot: "MIDNIGHT" }));
});
