import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { AiReviewService } from "./ai-review.service.js";

const requestId = "4b84bffe-e149-4208-b5af-dd0e068e40b2";
const existingId = "4b84bffe-e149-4208-b5af-dd0e068e40b3";
const base = {
  requestId,
  category: { name: "Pandan Bun", description: "Soft bun", displayOrder: 9,
    shelfLifeHours: 24, sellingPrice: 4.5 },
  recipe: [
    { ingredientId: existingId, newIngredient: null, gramsPerUnit: 65 },
    { ingredientId: null, newIngredient: { name: "Pandan paste", unit: "G",
      referenceUnitCost: 1.25, reorderThresholdGrams: 50, confirmed: true },
      gramsPerUnit: 5 },
  ],
};

test("reviewed bread passes one validated atomic RPC payload", async () => {
  const calls: unknown[] = [];
  const service = new AiReviewService({
    async catalogue() { return { categories: [], ingredients: [] }; },
    async create(...args) { calls.push(args); return { categoryId: "new" }; },
  });
  assert.deepEqual(await service.create("actor", base), { categoryId: "new" });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], ["actor", requestId, {
    category: base.category,
    recipe: [base.recipe[0], { ...base.recipe[1], newIngredient: {
      name: "Pandan paste", unit: "G", referenceUnitCost: 1.25,
      reorderThresholdGrams: 50 } }],
  }]);
});

test("unconfirmed, duplicate and malformed reviewed drafts never reach persistence", async () => {
  let called = 0;
  const service = new AiReviewService({
    async catalogue() { return { categories: [], ingredients: [] }; },
    async create() { called++; return {}; },
  });
  const invalid = [
    { ...base, recipe: [base.recipe[0], base.recipe[0]] },
    { ...base, recipe: [{ ...base.recipe[1], newIngredient: {
      ...base.recipe[1]!.newIngredient, confirmed: false } }] },
    { ...base, recipe: [{ ...base.recipe[0], gramsPerUnit: -1 }] },
    { ...base, category: { ...base.category, isActive: true } },
    { ...base, requestId: "not-a-uuid" },
  ];
  for (const input of invalid) await assert.rejects(service.create("actor", input),
    (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  assert.equal(called, 0);
});
