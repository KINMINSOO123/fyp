import assert from "node:assert/strict";
import { test } from "node:test";
import { CharityPartnerService, LeftoverManagementService } from
  "./leftover.service.js";
import type { LeftoverRepo } from "./leftover.repo.js";

const resultId = "10000000-0000-4000-8000-000000000001";
const charityId = "10000000-0000-4000-8000-000000000002";
const donationId = "10000000-0000-4000-8000-000000000003";

function repo(changes: Partial<LeftoverRepo> = {}): LeftoverRepo {
  return {
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async list() { return []; },
    async find() { return { dailyResultId: resultId, date: "2026-11-09",
      breadCategoryId: "bread-id", breadCategoryName: "Butter Sugar Bun",
      produced: 10, unitsSold: 5, leftover: 5, donated: 0, wasted: 0,
      remainingUnallocated: 5, dataOrigin: "SIMULATION_GENERATED" }; },
    async listCharities() { return []; },
    async allocate() { return {}; },
    async advanceStatus() { return {}; },
    async saveCharity() { return { id: charityId }; },
    async listDonations() { return { date: "2026-11-09", page: 1,
      pageSize: 50, total: 0, items: [] }; },
    ...changes,
  } as LeftoverRepo;
}

test("T-LEFT-AUTO-01 [FR-LDW-03, FR-LDW-04]: confirmed donation and waste send exact actor and positive quantity", async () => {
  const calls: unknown[] = [];
  const service = new LeftoverManagementService(repo({
    async allocate(actor, input) { calls.push({ actor, input }); return { ok: true }; },
  }));
  await service.donate("manager-id", { dailyResultId: resultId, quantity: 3,
    charityPartnerId: charityId, notes: null, confirm: true });
  await service.recordWaste("manager-id", { dailyResultId: resultId,
    quantity: 2, disposalReason: "Expired on shelf", confirm: true });
  assert.deepEqual(calls, [
    { actor: "manager-id", input: { action: "DONATE", dailyResultId: resultId,
      quantity: 3, charityPartnerId: charityId, disposalReason: null, notes: null } },
    { actor: "manager-id", input: { action: "WASTE", dailyResultId: resultId,
      quantity: 2, charityPartnerId: null,
      disposalReason: "Expired on shelf", notes: null } },
  ]);
});

test("T-LEFT-AUTO-02 [FR-LDW-03, FR-LDW-04, NFR-DAT-01]: invalid or unconfirmed allocations do not reach persistence", async () => {
  let writes = 0;
  const service = new LeftoverManagementService(repo({
    async allocate() { writes++; return {}; },
  }));
  for (const input of [
    { dailyResultId: resultId, quantity: 0, charityPartnerId: charityId,
      confirm: true },
    { dailyResultId: resultId, quantity: 2, charityPartnerId: charityId,
      confirm: false },
    { dailyResultId: resultId, quantity: 2, charityPartnerId: charityId,
      actorUserId: "forged", confirm: true },
  ]) await assert.rejects(service.donate("manager-id", input));
  await assert.rejects(service.recordWaste("manager-id", {
    dailyResultId: resultId, quantity: 1,
    disposalReason: "  ", confirm: true,
  }));
  assert.equal(writes, 0);
});

test("T-LEFT-AUTO-03 [FR-LDW-06]: status advances only by explicit confirmed steps; cancellation stays unsupported", async () => {
  const calls: string[] = [];
  const service = new LeftoverManagementService(repo({
    async advanceStatus(_actor, _id, status) { calls.push(status); return {}; },
  }));
  await service.advanceDonation("manager-id", donationId,
    { status: "COLLECTED", confirm: true });
  await service.advanceDonation("manager-id", donationId,
    { status: "COMPLETED", confirm: true });
  await assert.rejects(service.advanceDonation("manager-id", donationId,
    { status: "CANCELLED", confirm: true }));
  await assert.rejects(service.advanceDonation("manager-id", donationId,
    { status: "COMPLETED", confirm: false }));
  assert.deepEqual(calls, ["COLLECTED", "COMPLETED"]);
});

test("T-LEFT-AUTO-04 [FR-LDW-07]: charity administration validates fields and preserves actor", async () => {
  let saved: unknown;
  const service = new CharityPartnerService(repo({
    async saveCharity(actor, input) { saved = { actor, input }; return { id: charityId }; },
  }));
  await service.save("admin-id", {
    name: "Community Kitchen", contactInfo: null, isActive: true,
  });
  assert.deepEqual(saved, { actor: "admin-id", input: {
    id: null, name: "Community Kitchen", contactInfo: null, isActive: true,
  } });
  await assert.rejects(service.save("admin-id", {
    name: " ", contactInfo: null, isActive: true,
  }));
});
