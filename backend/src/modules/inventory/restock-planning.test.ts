import assert from "node:assert/strict";
import { test } from "node:test";
import type { PlanningInput } from "./recommendation-engine.js";
import { RecommendationEngine } from "./recommendation-engine.js";
import { buildRestockPreview } from "./restock-planning.js";

const date = "2026-11-12";
const input: PlanningInput = {
  targetDate: date,
  categories: ["a", "b", "c"].map((id, index) => ({
    id, name: id, displayOrder: index + 1 })),
  predictions: [{ id: "pa", breadCategoryId: "a", predictedUnitsSold: 6 },
    { id: "pb", breadCategoryId: "b", predictedUnitsSold: 4 },
    { id: "pc", breadCategoryId: "c", predictedUnitsSold: 8 }].map(
    (row) => ({ ...row, targetDate: date,
      predictionMode: "COLD_START" as const, confidence: null,
      lowConfidence: true })),
  ingredients: ["flour", "butter"].map((id) => ({
    id, name: id, isActive: true })),
  recipes: [
    { breadCategoryId: "a", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "a", ingredientId: "butter", gramsPerUnit: 20 },
    { breadCategoryId: "b", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "b", ingredientId: "butter", gramsPerUnit: 50 },
    { breadCategoryId: "c", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "c", ingredientId: "butter", gramsPerUnit: 10 },
  ],
  batches: [{ ingredientId: "flour", receivedDate: date,
    expiryDate: "2026-11-20", remainingGrams: 1000,
    status: "ACTIVE" }, { ingredientId: "butter", receivedDate: date,
    expiryDate: "2026-11-20", remainingGrams: 300,
    status: "ACTIVE" }],
  decisions: [{ id: "dc", predictionId: "pc", breadCategoryId: "c",
    finalSelectedQty: 2, recommendedProduction: 2, maxProducible: 10,
    selectedOption: "MANUAL_OVERRIDE", decisionReason: "Manager choice",
    processed: false }],
};

test("T-RST-01 [FR-INV-07, EXT-RST-01]: shared ingredient shortage survives feasible reduced recommendation", () => {
  const recommendation = new RecommendationEngine().build(input);
  assert.equal(recommendation.status, "READY");
  assert.equal(recommendation.entries.find((row) =>
    row.breadCategoryId === "b")?.recommendedProduction, 2);
  const restock = buildRestockPreview(input);
  assert.deepEqual(restock.desiredQuantities.map((row) => row.desiredQty),
    [6, 4, 2]);
  assert.deepEqual(restock.shortages.map((row) => [row.ingredientId,
    row.additionalGrams]), [["butter", 40], ["flour", 200]]);
});

test("T-RST-02 [FR-INV-07, EXT-RST-01]: processed production is excluded and refreshed stock removes shortage", () => {
  const processed = { ...input, decisions: [{ ...input.decisions[0]!,
    processed: true }] };
  assert.deepEqual(buildRestockPreview(processed).shortages.map((row) =>
    [row.ingredientId, row.additionalGrams]), [["butter", 20]]);
  const received = { ...input, batches: [...input.batches,
    { ingredientId: "flour", receivedDate: date,
      expiryDate: "2026-11-25", remainingGrams: 200,
      status: "ACTIVE" },
    { ingredientId: "butter", receivedDate: date,
      expiryDate: "2026-11-25", remainingGrams: 40,
      status: "ACTIVE" }] };
  assert.equal(buildRestockPreview(received).shortages.length, 0);
});
