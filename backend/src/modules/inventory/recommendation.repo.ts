import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import type { PlanningInput, PlanningDecision } from "./recommendation-engine.js";

function number(value: unknown, field: string): number {
  const parsed = Number(value);
  if (value === null || value === undefined || !Number.isFinite(parsed)) {
    throw new Error(`Invalid stored ${field}.`);
  }
  return parsed;
}

export class RecommendationRepo {
  async loadByPredictionId(predictionId: string): Promise<PlanningInput> {
    const { data, error } = await supabaseAdmin.from("daily_predictions")
      .select("target_date").eq("id", predictionId).maybeSingle();
    if (error) throw new Error("Unable to load the stored prediction.");
    if (!data) throw new AppError(404, "PREDICTION_NOT_FOUND", "The stored prediction was not found.");
    return this.load(data.target_date);
  }

  async load(targetDate: string): Promise<PlanningInput> {
    const [categories, predictions, ingredients, recipes, batches, decisions, productions] =
      await Promise.all([
        supabaseAdmin.from("bread_categories").select("id, name, display_order")
          .eq("is_active", true).order("display_order", { ascending: true }),
        supabaseAdmin.from("daily_predictions")
          .select("id, target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, context_snapshot")
          .eq("target_date", targetDate),
        supabaseAdmin.from("ingredients").select("id, name, is_active"),
        supabaseAdmin.from("recipes")
          .select("bread_category_id, ingredient_id, grams_per_unit"),
        supabaseAdmin.from("inventory_batches")
          .select("ingredient_id, received_date, expiry_date, remaining_quantity_grams, status")
          .eq("status", "ACTIVE").lte("received_date", targetDate)
          .gte("expiry_date", targetDate).gt("remaining_quantity_grams", 0),
        supabaseAdmin.from("production_decisions")
          .select("id, prediction_id, bread_category_id, final_selected_qty, recommended_production, max_producible, selected_option, decision_reason")
          .eq("target_date", targetDate),
        supabaseAdmin.from("daily_production")
          .select("production_decision_id").eq("production_date", targetDate),
      ]);
    const responses = [categories, predictions, ingredients, recipes, batches, decisions, productions];
    if (responses.some((response) => response.error || !response.data)) {
      throw new AppError(503, "PLANNING_DATA_UNAVAILABLE",
        "Unable to load the production planning data.");
    }
    const processedIds = new Set(productions.data!.map((row) => row.production_decision_id));
    return {
      targetDate,
      categories: categories.data!.map((row) => ({ id: row.id, name: row.name,
        displayOrder: number(row.display_order, "display order") })),
      predictions: predictions.data!.map((row) => ({ id: row.id,
        targetDate: row.target_date, breadCategoryId: row.bread_category_id,
        predictedUnitsSold: number(row.predicted_units_sold, "prediction"),
        predictionMode: row.prediction_mode as "MODEL" | "COLD_START",
        confidence: row.confidence === null ? null : number(row.confidence, "confidence"),
        lowConfidence: row.prediction_mode === "COLD_START" ||
          row.context_snapshot?.lowConfidence === true,
      })),
      ingredients: ingredients.data!.map((row) => ({ id: row.id, name: row.name,
        isActive: row.is_active === true })),
      recipes: recipes.data!.map((row) => ({ breadCategoryId: row.bread_category_id,
        ingredientId: row.ingredient_id,
        gramsPerUnit: number(row.grams_per_unit, "recipe quantity") })),
      batches: batches.data!.map((row) => ({ ingredientId: row.ingredient_id,
        receivedDate: row.received_date, expiryDate: row.expiry_date,
        remainingGrams: number(row.remaining_quantity_grams, "batch remainder"),
        status: row.status })),
      decisions: decisions.data!.map((row): PlanningDecision => ({ id: row.id,
        predictionId: row.prediction_id, breadCategoryId: row.bread_category_id,
        finalSelectedQty: number(row.final_selected_qty, "selected quantity"),
        recommendedProduction: number(row.recommended_production, "recommendation"),
        maxProducible: number(row.max_producible, "maximum"),
        selectedOption: row.selected_option,
        decisionReason: row.decision_reason,
        processed: processedIds.has(row.id),
      })),
    };
  }

  async confirm(actorUserId: string, input: {
    predictionId: string; finalSelectedQty: number;
    selectedOption: string; decisionReason: string | null;
  }): Promise<void> {
    const { error } = await supabaseAdmin.rpc("confirm_production_decision_with_audit", {
      p_actor_user_id: actorUserId,
      p_prediction_id: input.predictionId,
      p_final_selected_qty: input.finalSelectedQty,
      p_selected_option: input.selectedOption,
      p_decision_reason: input.decisionReason,
    });
    if (!error) return;
    if (error.code === "42501") throw new AppError(403, "FORBIDDEN", "Bakery Manager permission is required.");
    if (error.code === "P0002") throw new AppError(404, "PREDICTION_NOT_FOUND", "The stored prediction was not found.");
    if (error.code === "P0001") throw new AppError(409, "PLAN_SHORTAGE", error.message);
    if (error.code === "22023") throw new AppError(409, "PLAN_CHANGED", error.message);
    if (error.code === "PGRST202") throw new AppError(503, "PLANNING_SCHEMA_NOT_READY",
      "The production confirmation migration is not available.");
    throw new Error("Unable to confirm production.");
  }
}
