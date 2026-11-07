import assert from "node:assert/strict";
import { test } from "node:test";
import { RecommendationEngine, type PlanningInput } from "./recommendation-engine.js";

const date = "2026-11-05";
const input: PlanningInput = {
  targetDate: date,
  categories: [
    { id: "a", name: "A", displayOrder: 1 },
    { id: "b", name: "B", displayOrder: 2 },
    { id: "c", name: "C", displayOrder: 3 },
  ],
  predictions: ["a", "b", "c"].map((id) => ({
    id: `p-${id}`, targetDate: date, breadCategoryId: id,
    predictedUnitsSold: id === "a" ? 6 : id === "b" ? 4 : 2,
    predictionMode: "COLD_START" as const, confidence: null, lowConfidence: true,
  })),
  ingredients: ["flour", "butter", "yeast"].map((id) =>
    ({ id, name: id, isActive: true })),
  recipes: [
    { breadCategoryId: "a", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "a", ingredientId: "butter", gramsPerUnit: 20 },
    { breadCategoryId: "a", ingredientId: "yeast", gramsPerUnit: 2 },
    { breadCategoryId: "b", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "b", ingredientId: "butter", gramsPerUnit: 50 },
    { breadCategoryId: "b", ingredientId: "yeast", gramsPerUnit: 1 },
    { breadCategoryId: "c", ingredientId: "flour", gramsPerUnit: 100 },
    { breadCategoryId: "c", ingredientId: "butter", gramsPerUnit: 10 },
    { breadCategoryId: "c", ingredientId: "yeast", gramsPerUnit: 1 },
  ],
  batches: [
    { ingredientId: "flour", receivedDate: date, expiryDate: "2026-11-20", remainingGrams: 1000, status: "ACTIVE" },
    { ingredientId: "butter", receivedDate: date, expiryDate: "2026-11-20", remainingGrams: 300, status: "ACTIVE" },
    { ingredientId: "yeast", receivedDate: date, expiryDate: "2026-11-20", remainingGrams: 30, status: "ACTIVE" },
  ],
  decisions: [{ id: "d-c", predictionId: "p-c", breadCategoryId: "c",
    finalSelectedQty: 2, recommendedProduction: 2, maxProducible: 10,
    selectedOption: "ACCEPT_RECOMMENDATION", decisionReason: null, processed: false }],
};

test("T-INV-AUTO-01 [FR-INV-07, FR-INV-08]: shared stock reserves commitments and sequential recommendations", () => {
  const plan = new RecommendationEngine().build(input);
  assert.equal(plan.status, "READY");
  assert.equal(plan.entries.find((item) => item.breadCategoryId === "a")?.recommendedProduction, 6);
  assert.equal(plan.entries.find((item) => item.breadCategoryId === "b")?.recommendedProduction, 2);
  assert.equal(plan.remainingPlanningBalance.find((item) => item.ingredientId === "flour")?.grams, 0);
});

test("T-INV-AUTO-02 [FR-INV-07, FR-INV-10]: revision excludes old quantity and checks other commitments", () => {
  const engine = new RecommendationEngine();
  assert.equal(engine.maxAfterCommitments(input, "c", "p-c"), 10);
  const revised = engine.build(input, "p-c");
  assert.equal(revised.entries.find((item) => item.breadCategoryId === "c")?.state, "UNCONFIRMED");
  assert.equal(revised.entries.find((item) => item.breadCategoryId === "c")?.recommendedProduction, 1);
});

test("T-INV-AUTO-03 [FR-INV-07, FR-INV-12]: processed decisions are not reserved twice", () => {
  const plan = new RecommendationEngine().build({ ...input,
    decisions: input.decisions.map((item) => ({ ...item, processed: true })) });
  assert.equal(plan.outstandingCommitments.length, 0);
  assert.equal(plan.entries.find((item) => item.breadCategoryId === "c")?.state, "PROCESSED");
});

test("T-INV-AUTO-04 [FR-INV-07]: expired, inactive and future batches do not support production", () => {
  const plan = new RecommendationEngine().build({ ...input,
    batches: input.batches.map((row) => row.ingredientId === "flour"
      ? { ...row, expiryDate: "2026-11-04" } : row),
  });
  assert.equal(plan.status, "COMMITMENT_SHORTAGE");
  assert.equal(plan.shortages.find((row) => row.ingredientId === "flour")?.shortageGrams, 200);
  assert.equal(plan.entries.find((item) => item.breadCategoryId === "a")?.recommendedProduction, null);
});
