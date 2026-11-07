import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { RecommendationService } from "./recommendation.service.js";
import type { PlanningInput, PlanningDecision } from "./recommendation-engine.js";

const categoryA = "00000000-0000-4000-8000-000000000001";
const categoryB = "00000000-0000-4000-8000-000000000002";
const predictionA = "00000000-0000-4000-8000-000000000003";
const predictionB = "00000000-0000-4000-8000-000000000004";
const actor = "00000000-0000-4000-8000-000000000005";
const date = "2026-11-05";

function data(decisions: PlanningDecision[] = []): PlanningInput {
  return {
    targetDate: date,
    categories: [
      { id: categoryA, name: "A", displayOrder: 1 },
      { id: categoryB, name: "B", displayOrder: 2 },
    ],
    predictions: [
      { id: predictionA, targetDate: date, breadCategoryId: categoryA, predictedUnitsSold: 6,
        predictionMode: "COLD_START", confidence: null, lowConfidence: true },
      { id: predictionB, targetDate: date, breadCategoryId: categoryB, predictedUnitsSold: 6,
        predictionMode: "COLD_START", confidence: null, lowConfidence: true },
    ],
    ingredients: [{ id: "flour", name: "Flour", isActive: true }],
    recipes: [
      { breadCategoryId: categoryA, ingredientId: "flour", gramsPerUnit: 100 },
      { breadCategoryId: categoryB, ingredientId: "flour", gramsPerUnit: 100 },
    ],
    batches: [{ ingredientId: "flour", receivedDate: "2026-11-01",
      expiryDate: "2026-11-10", remainingGrams: 1000, status: "ACTIVE" }],
    decisions,
  };
}

test("T-INV-AUTO-05 [FR-INV-09, FR-INV-10]: confirmation replaces selected plan and recalculates later category", async () => {
  let current = data();
  let called = 0;
  const service = new RecommendationService({
    async load() { return current; },
    async loadByPredictionId() { return current; },
    async confirm(actorId, input) {
      assert.equal(actorId, actor);
      called++;
      current = data([{ id: "decision-a", predictionId: predictionA,
        breadCategoryId: categoryA, finalSelectedQty: input.finalSelectedQty,
        recommendedProduction: 6, maxProducible: 10,
        selectedOption: input.selectedOption,
        decisionReason: input.decisionReason, processed: false }]);
    },
  });
  const result = await service.confirm(actor, { predictionId: predictionA,
    finalSelectedQty: 6, selectedOption: "ACCEPT_RECOMMENDATION",
    decisionReason: null });
  assert.equal(called, 1);
  assert.equal(result.entries.find((row) => row.breadCategoryId === categoryB)?.recommendedProduction, 4);
  const revised = await service.confirm(actor, { predictionId: predictionA,
    finalSelectedQty: 3, selectedOption: "REDUCE", decisionReason: "Less dough today" });
  assert.equal(called, 2);
  assert.equal(revised.entries.find((row) => row.breadCategoryId === categoryB)?.recommendedProduction, 6);
});

test("T-INV-AUTO-06 [FR-INV-09, FR-INV-10]: rejects forged fields and processed revision", async () => {
  let called = false;
  const processed = data([{ id: "decision-a", predictionId: predictionA,
    breadCategoryId: categoryA, finalSelectedQty: 6,
    recommendedProduction: 6, maxProducible: 10,
    selectedOption: "ACCEPT_RECOMMENDATION", decisionReason: null,
    processed: true }]);
  const service = new RecommendationService({
    async load() { return processed; },
    async loadByPredictionId() { return processed; },
    async confirm() { called = true; },
  });
  await assert.rejects(service.confirm(actor, { predictionId: predictionA,
    finalSelectedQty: 6, selectedOption: "ACCEPT_RECOMMENDATION",
    decisionReason: null, feasible: true }), (error: unknown) =>
      error instanceof AppError && error.code === "VALIDATION_ERROR");
  await assert.rejects(service.confirm(actor, { predictionId: predictionA,
    finalSelectedQty: 3, selectedOption: "REDUCE",
    decisionReason: "Less" }), (error: unknown) =>
      error instanceof AppError && error.code === "DECISION_ALREADY_PROCESSED");
  assert.equal(called, false);
});

test("T-INV-AUTO-07 [FR-INV-10]: override must fit combined stock and state a reason", async () => {
  const service = new RecommendationService({
    async load() { return data(); },
    async loadByPredictionId() { return data(); },
    async confirm() { throw new Error("Should not reach persistence."); },
  });
  await assert.rejects(service.confirm(actor, { predictionId: predictionB,
    finalSelectedQty: 11, selectedOption: "MANUAL_OVERRIDE",
    decisionReason: "Special order" }), (error: unknown) =>
      error instanceof AppError && error.code === "PLAN_SHORTAGE");
  await assert.rejects(service.confirm(actor, { predictionId: predictionB,
    finalSelectedQty: 8, selectedOption: "MANUAL_OVERRIDE",
    decisionReason: " " }), (error: unknown) =>
      error instanceof AppError && error.code === "VALIDATION_ERROR");
});
