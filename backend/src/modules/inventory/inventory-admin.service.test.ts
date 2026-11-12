import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { InventoryAdminService } from "./inventory-admin.service.js";

const actor = "00000000-0000-4000-8000-000000000001";
const category = "00000000-0000-4000-8000-000000000002";
const ingredient = "00000000-0000-4000-8000-000000000003";

function service() {
  const calls: Array<{ actor: string; action: string; payload: Record<string, unknown> }> = [];
  const instance = new InventoryAdminService({
    async listCategories() { return []; },
    async listIngredients() { return []; },
    async listRecipes() { return []; },
    async listBatches() { return { items: [], page: 1, pageSize: 50, total: 0 }; },
    async mutate(actorId, action, payload) {
      calls.push({ actor: actorId, action, payload });
      return { id: category, action };
    },
  });
  return { instance, calls };
}

test("T-INV-AUTO-09 [FR-INV-01, NFR-DAT-01]: category and ingredient mutations accept only exact validated fields", async () => {
  const { instance, calls } = service();
  await instance.saveCategory(actor, {
    name: "Wholemeal", description: null, displayOrder: 1,
    shelfLifeHours: 24, sellingPrice: 5.5, isActive: false,
  });
  assert.equal(calls[0]?.action, "CREATE_CATEGORY");
  assert.equal(calls[0]?.actor, actor);
  await instance.saveIngredient(actor, {
    name: "Flour", unit: "KG", referenceUnitCost: 4.5,
    reorderThresholdGrams: 500, isActive: true,
  }, ingredient);
  assert.equal(calls[1]?.action, "UPDATE_INGREDIENT");
  assert.equal(calls[1]?.payload.id, ingredient);
  await assert.rejects(instance.saveCategory(actor, {
    name: "Wholemeal", description: null, displayOrder: 1,
    shelfLifeHours: 24, sellingPrice: 5.5, isActive: false,
    actorUserId: actor,
  }), (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  assert.equal(calls.length, 2);
});

test("T-INV-AUTO-10 [FR-INV-01, NFR-DAT-01]: recipe replacement rejects duplicates and nonpositive grams", async () => {
  const { instance, calls } = service();
  for (const items of [
    [{ ingredientId: ingredient, gramsPerUnit: 100 },
      { ingredientId: ingredient, gramsPerUnit: 50 }],
    [{ ingredientId: ingredient, gramsPerUnit: 0 }],
  ]) {
    await assert.rejects(instance.replaceRecipe(actor, category, { items }),
      (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  }
  assert.equal(calls.length, 0);
  await instance.replaceRecipe(actor, category, {
    items: [{ ingredientId: ingredient, gramsPerUnit: 125.5 }],
  });
  assert.equal(calls[0]?.action, "REPLACE_RECIPE");
});

test("T-INV-AUTO-11 [FR-INV-02, FR-INV-03]: batch receipt and removal validate dates, quantity and reason", async () => {
  const { instance, calls } = service();
  const receipt = { ingredientId: ingredient, receivedDate: "2026-11-04",
    expiryDate: "2026-11-07", quantityGrams: 500.5,
    unitCostSnapshot: 8.25, source: "Supplier" };
  await instance.receiveBatch(actor, receipt);
  assert.equal(calls[0]?.action, "RECEIVE_BATCH");
  await assert.rejects(instance.receiveBatch(actor, { ...receipt, expiryDate: "2026-11-03" }),
    (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  await assert.rejects(instance.receiveBatch(actor, { ...receipt, quantityGrams: -1 }),
    (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  await instance.adjustBatch(actor, ingredient, { removedGrams: 100,
    reason: "DISCARD", note: "Damaged packaging" });
  assert.equal(calls[1]?.action, "REMOVE_BATCH_STOCK");
  await assert.rejects(instance.adjustBatch(actor, ingredient, { removedGrams: 100,
    reason: "RESTOCK", note: "Wrong direction" }),
  (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  assert.equal(calls.length, 2);
});

test("T-RST-04 [FR-INV-02, EXT-RST-04]: linked receipt delegates once to atomic receipt path", async () => {
  const calls: unknown[] = [];
  const instance = new InventoryAdminService({
    async listCategories() { return []; },
    async listIngredients() { return []; },
    async listRecipes() { return []; },
    async listBatches() { return { items: [], page: 1, pageSize: 50, total: 0 }; },
    async mutate() { throw new Error("Standalone stock increment must not run."); },
  }, { async receiveLinked(...args) {
    calls.push(args);
    return { id: category, restockRequestId: category,
      alreadyRecorded: false };
  } });
  const receipt = { ingredientId: ingredient, receivedDate: "2026-11-11",
    expiryDate: "2026-11-15", quantityGrams: 100,
    unitCostSnapshot: 8.25, source: "Supplier",
    restockRequestItemId: category, receiptKey: actor };
  await instance.receiveBatch(actor, receipt);
  assert.equal(calls.length, 1);
  await assert.rejects(instance.receiveBatch(actor, { ...receipt,
    receiptKey: "invalid" }),
  (error) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  assert.equal(calls.length, 1);
});
