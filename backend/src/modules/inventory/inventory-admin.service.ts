import { AppError } from "../../shared/AppError.js";
import { isCalendarDate } from "../prediction/history-selection.service.js";
import type { InventoryAdminRepo } from "./inventory-admin.repo.js";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type DataRepo = Pick<InventoryAdminRepo,
  "listCategories" | "listIngredients" | "listRecipes" | "listBatches" | "mutate">;

function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== keys.length ||
      Object.keys(value).some((key) => !keys.includes(key))) {
    throw new AppError(400, "VALIDATION_ERROR", "Invalid inventory fields.");
  }
  return value as Record<string, unknown>;
}
function string(value: unknown, field: string, max = 120): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > max) {
    throw new AppError(400, "VALIDATION_ERROR", `${field} is required.`);
  }
  return value.trim();
}
function quantity(value: unknown, field: string, allowZero = true): number {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < (allowZero ? 0 : 0.001) ||
      Math.abs(value * 1000 - Math.round(value * 1000)) > 1e-6) {
    throw new AppError(400, "VALIDATION_ERROR", `${field} must have at most three decimal places.`);
  }
  return value;
}
function money(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 ||
      Math.abs(value * 100 - Math.round(value * 100)) > 1e-6) {
    throw new AppError(400, "VALIDATION_ERROR", `${field} must be a nonnegative MYR amount.`);
  }
  return value;
}
function id(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) {
    throw new AppError(400, "VALIDATION_ERROR", "A valid ID is required.");
  }
  return value;
}

export class InventoryAdminService {
  constructor(private readonly providedRepo?: DataRepo) {}
  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (await import("./inventory-admin.repo.js")).InventoryAdminRepo();
  }
  async listCategories() { return (await this.repo()).listCategories(); }
  async listIngredients() { return (await this.repo()).listIngredients(); }
  async listRecipes(categoryId: string) { return (await this.repo()).listRecipes(id(categoryId)); }
  async listBatches(query: unknown) {
    if (!query || typeof query !== "object" || Array.isArray(query) ||
        Object.keys(query).some((key) => !["ingredientId", "page"].includes(key))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid batch filters.");
    }
    const params = query as Record<string, unknown>;
    const ingredientId = params.ingredientId === undefined ? null : id(params.ingredientId);
    const page = params.page === undefined ? 1 : Number(params.page);
    if (!Number.isSafeInteger(page) || page < 1 || page > 10000) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid batch page.");
    }
    return (await this.repo()).listBatches(ingredientId, page);
  }

  async saveCategory(actor: string, input: unknown, categoryId?: string) {
    const raw = object(input, ["name", "description", "displayOrder", "shelfLifeHours", "sellingPrice", "isActive"]);
    const name = string(raw.name, "Category name");
    if (raw.description !== null && typeof raw.description !== "string") {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid category description.");
    }
    if (!Number.isSafeInteger(raw.displayOrder) || (raw.displayOrder as number) < 0 ||
        !Number.isSafeInteger(raw.shelfLifeHours) || (raw.shelfLifeHours as number) <= 0 ||
        typeof raw.isActive !== "boolean") {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid category order, shelf life or status.");
    }
    return (await this.repo()).mutate(actor, categoryId ? "UPDATE_CATEGORY" : "CREATE_CATEGORY", {
      ...(categoryId ? { id: id(categoryId) } : {}), name,
      description: raw.description === null ? null : raw.description.trim() || null,
      displayOrder: raw.displayOrder, shelfLifeHours: raw.shelfLifeHours,
      sellingPrice: money(raw.sellingPrice, "Selling price"), isActive: raw.isActive,
    });
  }

  async saveIngredient(actor: string, input: unknown, ingredientId?: string) {
    const raw = object(input, ["name", "unit", "referenceUnitCost", "reorderThresholdGrams", "isActive"]);
    const name = string(raw.name, "Ingredient name");
    if (raw.unit !== "G" && raw.unit !== "KG" || typeof raw.isActive !== "boolean") {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid ingredient unit or status.");
    }
    return (await this.repo()).mutate(actor, ingredientId ? "UPDATE_INGREDIENT" : "CREATE_INGREDIENT", {
      ...(ingredientId ? { id: id(ingredientId) } : {}), name, unit: raw.unit,
      referenceUnitCost: money(raw.referenceUnitCost, "Reference unit cost"),
      reorderThresholdGrams: quantity(raw.reorderThresholdGrams, "Reorder threshold"),
      isActive: raw.isActive,
    });
  }

  async replaceRecipe(actor: string, categoryId: string, input: unknown) {
    const raw = object(input, ["items"]);
    if (!Array.isArray(raw.items) || raw.items.length === 0 || raw.items.length > 100) {
      throw new AppError(400, "VALIDATION_ERROR", "At least one recipe ingredient is required.");
    }
    const seen = new Set<string>();
    const items = raw.items.map((item: unknown) => {
      const row = object(item, ["ingredientId", "gramsPerUnit"]);
      const ingredientId = id(row.ingredientId);
      if (seen.has(ingredientId)) throw new AppError(400, "VALIDATION_ERROR", "Duplicate recipe ingredient.");
      seen.add(ingredientId);
      return { ingredientId,
        gramsPerUnit: quantity(row.gramsPerUnit, "Recipe grams", false) };
    });
    return (await this.repo()).mutate(actor, "REPLACE_RECIPE", {
      breadCategoryId: id(categoryId), items,
    });
  }

  async receiveBatch(actor: string, input: unknown) {
    const raw = object(input, ["ingredientId", "receivedDate", "expiryDate", "quantityGrams", "unitCostSnapshot", "source"]);
    const receivedDate = string(raw.receivedDate, "Receipt date", 10);
    const expiryDate = string(raw.expiryDate, "Expiry date", 10);
    if (!isCalendarDate(receivedDate) || !isCalendarDate(expiryDate) || expiryDate <= receivedDate ||
        (raw.source !== null && (typeof raw.source !== "string" || !raw.source.trim()))) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid batch dates or source.");
    }
    return (await this.repo()).mutate(actor, "RECEIVE_BATCH", {
      ingredientId: id(raw.ingredientId), receivedDate, expiryDate,
      quantityGrams: quantity(raw.quantityGrams, "Receipt quantity", false),
      unitCostSnapshot: money(raw.unitCostSnapshot, "Batch unit cost"),
      source: raw.source === null ? null : (raw.source as string).trim(),
    });
  }

  async adjustBatch(actor: string, batchId: string, input: unknown) {
    const raw = object(input, ["removedGrams", "reason", "note"]);
    if (raw.reason !== "DISCARD" && raw.reason !== "CORRECTION") {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid adjustment reason.");
    }
    return (await this.repo()).mutate(actor, "REMOVE_BATCH_STOCK", {
      batchId: id(batchId), removedGrams: quantity(raw.removedGrams, "Removed quantity", false),
      reason: raw.reason, note: string(raw.note, "Adjustment note", 500),
    });
  }
}
