import { RecommendationEngine } from "./recommendation-engine.js";
import type { PlanningInput } from "./recommendation-engine.js";
import { AppError } from "../../shared/AppError.js";

export type RestockPreview = {
  targetDate: string;
  desiredQuantities: Array<{ breadCategoryId: string; breadCategoryName: string;
    desiredQty: number; basis: "PREDICTION" | "CONFIRMED" }>;
  shortages: Array<{ ingredientId: string; ingredientName: string;
    requiredGrams: number; availableGrams: number; additionalGrams: number }>;
};

function milli(value: number): number {
  const scaled = Math.round(value * 1000);
  if (!Number.isFinite(value) || !Number.isSafeInteger(scaled) ||
      Math.abs(value * 1000 - scaled) > 1e-6) {
    throw new AppError(409, "PLANNING_DATA_INVALID",
      "Ingredient grams exceed supported precision.");
  }
  return scaled;
}

export function buildRestockPreview(input: PlanningInput,
  engine = new RecommendationEngine()): RestockPreview {
  // Reuse the validated recipe, prediction and commitment graph. A feasible
  // reduced recommendation does not erase unmet desired production.
  const plan = engine.build(input);
  const available = new Map<string, number>();
  for (const batch of input.batches) {
    if (batch.status !== "ACTIVE" || batch.receivedDate > input.targetDate ||
        batch.expiryDate < input.targetDate) continue;
    available.set(batch.ingredientId,
      (available.get(batch.ingredientId) ?? 0) + milli(batch.remainingGrams));
  }
  const required = new Map<string, { name: string; milli: number }>();
  const desiredQuantities: RestockPreview["desiredQuantities"] = [];
  for (const entry of plan.entries) {
    if (entry.state === "PROCESSED") continue;
    const desiredQty = entry.state === "CONFIRMED"
      ? entry.finalSelectedQty! : entry.predictedUnitsSold;
    desiredQuantities.push({ breadCategoryId: entry.breadCategoryId,
      breadCategoryName: entry.breadCategoryName, desiredQty,
      basis: entry.state === "CONFIRMED" ? "CONFIRMED" : "PREDICTION" });
    for (const ingredient of entry.ingredientRequirements) {
      const previous = required.get(ingredient.ingredientId);
      const total = (previous?.milli ?? 0) +
        milli(ingredient.gramsPerUnit) * desiredQty;
      if (!Number.isSafeInteger(total)) throw new AppError(409,
        "PLANNING_DATA_INVALID", "Desired ingredient total is too large.");
      required.set(ingredient.ingredientId, {
        name: ingredient.ingredientName,
        milli: total,
      });
    }
  }
  const shortages: RestockPreview["shortages"] = [];
  for (const [ingredientId, demand] of required) {
    const stock = available.get(ingredientId) ?? 0;
    if (demand.milli <= stock) continue;
    shortages.push({ ingredientId, ingredientName: demand.name,
      requiredGrams: demand.milli / 1000,
      availableGrams: stock / 1000,
      additionalGrams: (demand.milli - stock) / 1000 });
  }
  shortages.sort((a, b) => a.ingredientId.localeCompare(b.ingredientId));
  return { targetDate: input.targetDate, desiredQuantities, shortages };
}
