import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { RestockService } from "./restock.service.js";
import type { PlanningInput } from "./recommendation-engine.js";

const date = "2026-11-12";
const input: PlanningInput = {
  targetDate: date,
  categories: [{ id: "a", name: "Bread", displayOrder: 1 }],
  predictions: [{ id: "p", targetDate: date, breadCategoryId: "a",
    predictedUnitsSold: 10, predictionMode: "COLD_START",
    confidence: null, lowConfidence: true }],
  ingredients: [{ id: "flour", name: "Flour", isActive: true }],
  recipes: [{ breadCategoryId: "a", ingredientId: "flour",
    gramsPerUnit: 100 }],
  batches: [{ ingredientId: "flour", receivedDate: date,
    expiryDate: "2026-11-20", remainingGrams: 500, status: "ACTIVE" }],
  decisions: [],
};

test("T-RST-03 [EXT-RST-02]: submit confirms current server plan; stale or unconfirmed requests do not persist", async () => {
  let writes = 0;
  const service = new RestockService({
    async loadPlanning() { return input; },
    async submit(_actor, targetDate, snapshot) {
      writes += 1;
      assert.equal(targetDate, date);
      assert.deepEqual(snapshot, { desiredQuantities: [{
        breadCategoryId: "a", desiredQty: 10 }],
      shortages: [{ ingredientId: "flour", additionalGrams: 500 }] });
      return { id: "request", productionDate: date, status: "PENDING" };
    },
    async list() { return []; },
    async cancel() { return { id: "request", status: "CANCELLED" }; },
  });
  const preview = await service.preview(date);
  const expectedPlan = { desiredQuantities: preview.desiredQuantities.map(
    (row) => ({ breadCategoryId: row.breadCategoryId,
      desiredQty: row.desiredQty })),
    shortages: preview.shortages.map((row) => ({
      ingredientId: row.ingredientId,
      additionalGrams: row.additionalGrams })) };
  await assert.rejects(service.submit("manager", { targetDate: date,
    expectedPlan, confirmed: false }));
  await assert.rejects(service.submit("manager", { targetDate: date,
    expectedPlan: { ...expectedPlan, shortages: [] }, confirmed: true }),
  (error: unknown) => error instanceof AppError &&
    error.code === "RESTOCK_PLAN_CHANGED");
  assert.equal(writes, 0);
  await service.submit("manager", { targetDate: date,
    expectedPlan, confirmed: true });
  assert.equal(writes, 1);
});
