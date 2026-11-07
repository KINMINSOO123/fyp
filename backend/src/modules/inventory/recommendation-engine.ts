import { AppError } from "../../shared/AppError.js";

export interface PlanningCategory { id: string; name: string; displayOrder: number; }
export interface PlanningPrediction {
  id: string; targetDate: string; breadCategoryId: string;
  predictedUnitsSold: number; predictionMode: "MODEL" | "COLD_START";
  confidence: number | null; lowConfidence: boolean;
}
export interface PlanningIngredient { id: string; name: string; isActive: boolean; }
export interface PlanningRecipe { breadCategoryId: string; ingredientId: string; gramsPerUnit: number; }
export interface PlanningBatch { ingredientId: string; receivedDate: string; expiryDate: string; remainingGrams: number; status: string; }
export interface PlanningDecision {
  id: string; predictionId: string; breadCategoryId: string;
  finalSelectedQty: number; recommendedProduction: number; maxProducible: number;
  selectedOption: string; decisionReason: string | null; processed: boolean;
}
export interface PlanningInput {
  targetDate: string;
  categories: PlanningCategory[];
  predictions: PlanningPrediction[];
  ingredients: PlanningIngredient[];
  recipes: PlanningRecipe[];
  batches: PlanningBatch[];
  decisions: PlanningDecision[];
}
export interface IngredientShortage {
  ingredientId: string; ingredientName: string;
  availableGrams: number; committedGrams: number; shortageGrams: number;
}
export interface RecommendationEntry {
  breadCategoryId: string; breadCategoryName: string; displayOrder: number;
  predictionId: string; predictedUnitsSold: number;
  predictionMode: "MODEL" | "COLD_START";
  confidence: number | null; lowConfidence: boolean;
  state: "UNCONFIRMED" | "CONFIRMED" | "PROCESSED";
  recommendedProduction: number | null; maxProducible: number | null;
  finalSelectedQty: number | null; selectedOption: string | null;
  decisionReason: string | null;
  ingredientRequirements: Array<{ ingredientId: string; ingredientName: string; gramsPerUnit: number; recommendedGrams: number | null }>;
}
export interface RecommendationPlan {
  targetDate: string; status: "READY" | "COMMITMENT_SHORTAGE";
  entries: RecommendationEntry[]; shortages: IngredientShortage[];
  remainingPlanningBalance: Array<{ ingredientId: string; ingredientName: string; grams: number }>;
  outstandingCommitments: Array<{ decisionId: string; breadCategoryId: string; finalSelectedQty: number }>;
}

function milli(value: number, field: string): number {
  const scaled = Math.round(value * 1000);
  if (!Number.isFinite(value) || value < 0 || !Number.isSafeInteger(scaled) ||
      Math.abs(value * 1000 - scaled) > 1e-6) {
    throw new AppError(409, "PLANNING_DATA_INVALID", `${field} must be a nonnegative gram quantity with three decimal places.`);
  }
  return scaled;
}

function whole(value: number, field: string): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new AppError(409, "PLANNING_DATA_INVALID", `${field} must be a nonnegative whole quantity.`);
  }
  return value;
}

export class RecommendationEngine {
  build(input: PlanningInput, excludedPredictionId?: string): RecommendationPlan {
    const categories = [...input.categories].sort((a, b) =>
      a.displayOrder - b.displayOrder || a.id.localeCompare(b.id));
    if (!/^\d{4}-\d{2}-\d{2}$/.test(input.targetDate) || categories.length === 0) {
      throw new AppError(409, "PLANNING_DATA_INVALID", "A production date and active categories are required.");
    }
    const ingredients = new Map(input.ingredients.map((row) => [row.id, row]));
    const recipes = new Map<string, Array<{ ingredientId: string; gramsMilli: number }>>();
    const relevantCategories = new Set([
      ...categories.map((row) => row.id),
      ...input.decisions.filter((row) => !row.processed).map((row) => row.breadCategoryId),
    ]);
    for (const row of input.recipes) {
      if (!relevantCategories.has(row.breadCategoryId)) continue;
      const ingredient = ingredients.get(row.ingredientId);
      if (!ingredient || !ingredient.isActive) {
        throw new AppError(409, "RECIPE_CONFIG_INCOMPLETE", "An active recipe contains an inactive or missing ingredient.");
      }
      const gramsMilli = milli(row.gramsPerUnit, "Recipe quantity");
      if (gramsMilli <= 0) {
        throw new AppError(409, "RECIPE_CONFIG_INCOMPLETE", "Recipe quantities must be positive.");
      }
      const rows = recipes.get(row.breadCategoryId) ?? [];
      if (rows.some((item) => item.ingredientId === row.ingredientId)) {
        throw new AppError(409, "RECIPE_CONFIG_INCOMPLETE", "A recipe has a duplicate ingredient.");
      }
      rows.push({ ingredientId: row.ingredientId, gramsMilli });
      recipes.set(row.breadCategoryId, rows);
    }
    const recipeFor = (categoryId: string) => {
      const rows = recipes.get(categoryId);
      if (!rows?.length) throw new AppError(409, "RECIPE_CONFIG_INCOMPLETE", "Every planned category needs a valid recipe.");
      return rows;
    };
    const predictions = new Map(input.predictions.map((row) => [row.breadCategoryId, row]));
    const balance = new Map(input.ingredients.map((row) => [row.id, 0]));
    for (const batch of input.batches) {
      if (batch.status !== "ACTIVE" || batch.receivedDate > input.targetDate ||
          batch.expiryDate < input.targetDate) continue;
      if (!ingredients.has(batch.ingredientId)) {
        throw new AppError(409, "PLANNING_DATA_INVALID", "A valid batch refers to a missing ingredient.");
      }
      const amount = milli(batch.remainingGrams, "Batch remainder");
      balance.set(batch.ingredientId, (balance.get(batch.ingredientId) ?? 0) + amount);
    }
    const stock = new Map(balance);
    const outstanding = input.decisions.filter((row) =>
      !row.processed && row.predictionId !== excludedPredictionId);
    for (const decision of outstanding) {
      const qty = whole(decision.finalSelectedQty, "Confirmed quantity");
      for (const row of recipeFor(decision.breadCategoryId)) {
        balance.set(row.ingredientId,
          (balance.get(row.ingredientId) ?? 0) - row.gramsMilli * qty);
      }
    }
    const shortages: IngredientShortage[] = [];
    for (const [id, remaining] of balance) {
      if (remaining >= 0) continue;
      shortages.push({ ingredientId: id, ingredientName: ingredients.get(id)?.name ?? id,
        availableGrams: (stock.get(id) ?? 0) / 1000,
        committedGrams: ((stock.get(id) ?? 0) - remaining) / 1000,
        shortageGrams: -remaining / 1000 });
    }
    const decisions = new Map(input.decisions.filter((row) =>
      row.predictionId !== excludedPredictionId).map((row) => [row.breadCategoryId, row]));
    const entries: RecommendationEntry[] = [];
    for (const category of categories) {
      const prediction = predictions.get(category.id);
      if (!prediction || prediction.targetDate !== input.targetDate ||
          !Number.isSafeInteger(prediction.predictedUnitsSold) ||
          prediction.predictedUnitsSold < 0 ||
          (prediction.predictionMode === "MODEL" &&
            (prediction.confidence === null || !Number.isFinite(prediction.confidence) ||
             prediction.confidence < 0 || prediction.confidence > 100)) ||
          (prediction.predictionMode === "COLD_START" && prediction.confidence !== null) ||
          !["MODEL", "COLD_START"].includes(prediction.predictionMode)) {
        throw new AppError(409, "PREDICTION_INCOMPLETE", `A stored prediction is required for ${category.name}.`);
      }
      const recipe = recipeFor(category.id);
      const decision = decisions.get(category.id);
      const state = decision?.processed ? "PROCESSED" : decision ? "CONFIRMED" : "UNCONFIRMED";
      let maxProducible: number | null = decision?.maxProducible ?? null;
      let recommendedProduction: number | null = decision?.recommendedProduction ?? null;
      if (!decision && shortages.length === 0) {
        maxProducible = Math.min(...recipe.map((row) =>
          Math.floor(Math.max(0, balance.get(row.ingredientId) ?? 0) / row.gramsMilli)));
        recommendedProduction = Math.min(prediction.predictedUnitsSold, maxProducible);
        for (const row of recipe) {
          balance.set(row.ingredientId,
            (balance.get(row.ingredientId) ?? 0) - row.gramsMilli * recommendedProduction);
        }
      }
      entries.push({ breadCategoryId: category.id, breadCategoryName: category.name,
        displayOrder: category.displayOrder, predictionId: prediction.id,
        predictedUnitsSold: prediction.predictedUnitsSold,
        predictionMode: prediction.predictionMode,
        confidence: prediction.confidence, lowConfidence: prediction.lowConfidence,
        state,
        recommendedProduction, maxProducible,
        finalSelectedQty: decision?.finalSelectedQty ?? null,
        selectedOption: decision?.selectedOption ?? null,
        decisionReason: decision?.decisionReason ?? null,
        ingredientRequirements: recipe.map((row) => ({
          ingredientId: row.ingredientId,
          ingredientName: ingredients.get(row.ingredientId)?.name ?? row.ingredientId,
          gramsPerUnit: row.gramsMilli / 1000,
          recommendedGrams: recommendedProduction === null ? null :
            row.gramsMilli * recommendedProduction / 1000,
        })),
      });
    }
    return { targetDate: input.targetDate,
      status: shortages.length ? "COMMITMENT_SHORTAGE" : "READY",
      entries, shortages,
      remainingPlanningBalance: [...balance].map(([id, grams]) => ({
        ingredientId: id, ingredientName: ingredients.get(id)?.name ?? id,
        grams: grams / 1000,
      })),
      outstandingCommitments: outstanding.map((row) => ({
        decisionId: row.id, breadCategoryId: row.breadCategoryId,
        finalSelectedQty: row.finalSelectedQty,
      })),
    };
  }

  maxAfterCommitments(input: PlanningInput, categoryId: string, excludedPredictionId?: string): number {
    const category = input.categories.find((row) => row.id === categoryId);
    if (!category) throw new AppError(409, "CATEGORY_INACTIVE", "The bread category is not active.");
    const otherDecisions = input.decisions.filter((row) =>
      !row.processed && row.predictionId !== excludedPredictionId);
    const remaining = new Map(input.ingredients.map((row) => [row.id, 0]));
    for (const batch of input.batches) {
      if (batch.status === "ACTIVE" && batch.receivedDate <= input.targetDate &&
          batch.expiryDate >= input.targetDate) {
        remaining.set(batch.ingredientId, (remaining.get(batch.ingredientId) ?? 0) +
          milli(batch.remainingGrams, "Batch remainder"));
      }
    }
    for (const decision of otherDecisions) {
      for (const recipe of input.recipes.filter((row) => row.breadCategoryId === decision.breadCategoryId)) {
        remaining.set(recipe.ingredientId,
          (remaining.get(recipe.ingredientId) ?? 0) -
          milli(recipe.gramsPerUnit, "Recipe quantity") * decision.finalSelectedQty);
      }
    }
    const recipe = input.recipes.filter((row) => row.breadCategoryId === categoryId);
    if (!recipe.length) throw new AppError(409, "RECIPE_CONFIG_INCOMPLETE", "A valid recipe is required.");
    return Math.min(...recipe.map((row) => Math.floor(
      Math.max(0, remaining.get(row.ingredientId) ?? 0) /
      milli(row.gramsPerUnit, "Recipe quantity"))));
  }
}
