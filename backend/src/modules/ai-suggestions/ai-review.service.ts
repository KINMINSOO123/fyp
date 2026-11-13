import { AppError } from "../../shared/AppError.js";
import type { AiReviewRepo } from "./ai-review.repo.js";

type Repo = Pick<AiReviewRepo, "catalogue" | "create">;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== keys.length ||
      Object.keys(value).some((key) => !keys.includes(key)))
    throw new AppError(400, "VALIDATION_ERROR", "Invalid reviewed bread fields.");
  return value as Record<string, unknown>;
}
function name(value: unknown, max = 120): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > max)
    throw new AppError(400, "VALIDATION_ERROR", "A valid name is required.");
  return value.trim();
}
function grams(value: unknown, positive = false): number {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < (positive ? 0.001 : 0) ||
      Math.abs(value * 1000 - Math.round(value * 1000)) > 1e-6)
    throw new AppError(400, "VALIDATION_ERROR", "Gram values must be nonnegative with at most three decimals.");
  return value;
}
function money(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 ||
      Math.abs(value * 100 - Math.round(value * 100)) > 1e-6)
    throw new AppError(400, "VALIDATION_ERROR", "Prices must be nonnegative MYR amounts.");
  return value;
}

export class AiReviewService {
  constructor(private readonly providedRepo?: Repo) {}
  private async repo(): Promise<Repo> {
    return this.providedRepo ?? new (await import("./ai-review.repo.js")).AiReviewRepo();
  }
  async catalogue() { return (await this.repo()).catalogue(); }
  async create(actorUserId: string, body: unknown) {
    const raw = object(body, ["requestId", "category", "recipe"]);
    if (typeof raw.requestId !== "string" || !uuid.test(raw.requestId))
      throw new AppError(400, "VALIDATION_ERROR", "A valid request ID is required.");
    const category = object(raw.category,
      ["name", "description", "displayOrder", "shelfLifeHours", "sellingPrice"]);
    if (category.description !== null && typeof category.description !== "string")
      throw new AppError(400, "VALIDATION_ERROR", "Invalid category description.");
    if (!Number.isSafeInteger(category.displayOrder) || (category.displayOrder as number) < 0 ||
        !Number.isSafeInteger(category.shelfLifeHours) || (category.shelfLifeHours as number) <= 0)
      throw new AppError(400, "VALIDATION_ERROR", "Invalid category order or shelf life.");
    if (!Array.isArray(raw.recipe) || raw.recipe.length < 1 || raw.recipe.length > 15)
      throw new AppError(400, "VALIDATION_ERROR", "A recipe needs 1 to 15 ingredients.");
    const seen = new Set<string>();
    const recipe = raw.recipe.map((item: unknown) => {
      const row = object(item, ["ingredientId", "newIngredient", "gramsPerUnit"]);
      const amount = grams(row.gramsPerUnit, true);
      if (amount > 2000) throw new AppError(400, "VALIDATION_ERROR", "Recipe grams exceed the draft limit.");
      if (row.ingredientId !== null && row.newIngredient !== null)
        throw new AppError(400, "VALIDATION_ERROR", "Choose an existing or new ingredient.");
      if (row.ingredientId !== null) {
        if (typeof row.ingredientId !== "string" || !uuid.test(row.ingredientId) ||
            seen.has(row.ingredientId))
          throw new AppError(400, "VALIDATION_ERROR", "Invalid or duplicate ingredient ID.");
        seen.add(row.ingredientId);
        return { ingredientId: row.ingredientId, newIngredient: null,
          gramsPerUnit: amount };
      }
      const ingredient = object(row.newIngredient,
        ["name", "unit", "referenceUnitCost", "reorderThresholdGrams", "confirmed"]);
      if (ingredient.confirmed !== true || !["G", "KG"].includes(String(ingredient.unit)))
        throw new AppError(400, "VALIDATION_ERROR", "Confirm each new ingredient and its unit.");
      const ingredientName = name(ingredient.name);
      const identity = ingredientName.toLocaleLowerCase("en");
      if (seen.has(identity)) throw new AppError(400, "VALIDATION_ERROR", "Duplicate recipe ingredient.");
      seen.add(identity);
      return { ingredientId: null, newIngredient: {
        name: ingredientName, unit: ingredient.unit as "G" | "KG",
        referenceUnitCost: money(ingredient.referenceUnitCost),
        reorderThresholdGrams: grams(ingredient.reorderThresholdGrams),
      }, gramsPerUnit: amount };
    });
    return (await this.repo()).create(actorUserId, raw.requestId, {
      category: { name: name(category.name),
        description: category.description === null ? null :
          category.description.trim() || null,
        displayOrder: category.displayOrder as number,
        shelfLifeHours: category.shelfLifeHours as number,
        sellingPrice: money(category.sellingPrice) }, recipe,
    });
  }
}
