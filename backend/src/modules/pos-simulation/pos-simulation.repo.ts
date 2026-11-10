import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export interface SimulationItem {
  breadCategoryId: string;
  breadCategoryName: string;
  predictionId: string;
  productionDecisionId: string;
  dailyProductionId: string;
  dailyResultId: string;
  predictedUnitsSold: number;
  predictionMode: "MODEL" | "COLD_START";
  confidence: number | null;
  modelVersionId: string | null;
  produced: number;
  unitsSold: number;
  lostSales: number;
  estimatedDemand: number;
  leftover: number;
  remainingUnallocatedLeftover: number;
  salesPredictionError: number;
  leftoverRatePct: number | null;
  revenue: number;
  ingredientCost: number;
  grossProfit: number;
  dataOrigin: "SIMULATION_GENERATED";
}

export interface SimulationResult {
  date: string;
  operationId: string | null;
  items: SimulationItem[];
}

function number(value: unknown, field: string): number {
  const result = Number(value);
  if (value === null || value === undefined || !Number.isFinite(result)) {
    throw new Error(`Invalid stored ${field}.`);
  }
  return result;
}

export class PosSimulationRepo {
  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new AppError(503, "BAKERY_SETTINGS_UNAVAILABLE",
        "Bakery timezone is unavailable.");
    }
    return data.timezone;
  }

  async complete(actorUserId: string, date: string): Promise<SimulationResult> {
    const { data, error } = await supabaseAdmin.rpc("complete_pos_simulation", {
      p_actor_user_id: actorUserId, p_date: date,
    });
    if (error) {
      if (error.code === "42501") throw new AppError(403, "FORBIDDEN", error.message);
      if (error.code === "22023") throw new AppError(400, "VALIDATION_ERROR", error.message);
      if (error.code === "P1001" || error.code === "23505") {
        throw new AppError(409, "ALREADY_SIMULATED",
          `This date is already simulated. Open /api/simulations/${date} to view its results.`);
      }
      if (error.code === "P1002") throw new AppError(409, "CONFIRMATION_REQUIRED", error.message);
      if (error.code === "P1003") throw new AppError(409, "PLAN_SHORTAGE", error.message);
      if (error.code === "P1004") throw new AppError(409, "SIMULATION_CONFIG_INVALID", error.message);
      if (error.code === "PGRST202" || error.code === "42883") {
        throw new AppError(503, "SIMULATION_SCHEMA_NOT_READY",
          "The atomic POS simulation migration is not available.");
      }
      throw new Error("Unable to complete POS simulation.");
    }
    if (!data || typeof data !== "object" || Array.isArray(data) ||
        data.date !== date || !Array.isArray(data.items) ||
        data.items.length === 0 ||
        typeof data.operationId !== "string") {
      throw new Error("The simulation returned an invalid result.");
    }
    return data as SimulationResult;
  }

  async getResult(date: string): Promise<SimulationResult> {
    const [results, categories, productions, predictions] = await Promise.all([
      supabaseAdmin.from("daily_results").select(
        "id, result_date, bread_category_id, prediction_id, daily_production_id, predicted_units_sold, produced, units_sold, lost_sales, estimated_demand, leftover, remaining_unallocated_leftover, sales_prediction_error, leftover_rate_pct, revenue, ingredient_cost, gross_profit")
        .eq("result_date", date),
      supabaseAdmin.from("bread_categories").select("id, name, display_order"),
      supabaseAdmin.from("daily_production").select(
        "id, production_decision_id").eq("production_date", date),
      supabaseAdmin.from("daily_predictions").select(
        "id, prediction_mode, confidence, model_version_id").eq("target_date", date),
    ]);
    if (results.error || categories.error || productions.error || predictions.error ||
        !results.data || !categories.data || !productions.data || !predictions.data) {
      throw new AppError(503, "SIMULATION_DATA_UNAVAILABLE",
        "Unable to load simulation results.");
    }
    const byCategory = new Map(categories.data.map((row) => [row.id, row]));
    const byProduction = new Map(productions.data.map((row) => [row.id, row]));
    const byPrediction = new Map(predictions.data.map((row) => [row.id, row]));
    const items: SimulationItem[] = results.data.map((row) => {
      const category = byCategory.get(row.bread_category_id);
      const production = byProduction.get(row.daily_production_id);
      const prediction = byPrediction.get(row.prediction_id);
      if (!category || !production || !prediction) {
        throw new Error("Simulation links are incomplete.");
      }
      return {
        breadCategoryId: row.bread_category_id,
        breadCategoryName: category.name,
        predictionId: row.prediction_id,
        productionDecisionId: production.production_decision_id,
        dailyProductionId: row.daily_production_id,
        dailyResultId: row.id,
        predictedUnitsSold: number(row.predicted_units_sold, "prediction"),
        predictionMode: prediction.prediction_mode as "MODEL" | "COLD_START",
        confidence: prediction.confidence === null ? null :
          number(prediction.confidence, "confidence"),
        modelVersionId: prediction.model_version_id,
        produced: number(row.produced, "production"),
        unitsSold: number(row.units_sold, "sales"),
        lostSales: number(row.lost_sales, "lost sales"),
        estimatedDemand: number(row.estimated_demand, "estimated demand"),
        leftover: number(row.leftover, "leftover"),
        remainingUnallocatedLeftover: number(row.remaining_unallocated_leftover, "unallocated leftover"),
        salesPredictionError: number(row.sales_prediction_error, "prediction error"),
        leftoverRatePct: row.leftover_rate_pct === null ? null :
          number(row.leftover_rate_pct, "leftover rate"),
        revenue: number(row.revenue, "revenue"),
        ingredientCost: number(row.ingredient_cost, "ingredient cost"),
        grossProfit: number(row.gross_profit, "gross profit"),
        dataOrigin: "SIMULATION_GENERATED",
      };
    });
    items.sort((left, right) =>
      number(byCategory.get(left.breadCategoryId)?.display_order, "display order") -
      number(byCategory.get(right.breadCategoryId)?.display_order, "display order"));
    return { date, operationId: null, items };
  }

  async getTransactions(date: string, input: {
    breadCategoryId?: string; timeSlot?: string; page: number;
  }) {
    const resultIds = await supabaseAdmin.from("daily_results")
      .select("id, bread_category_id").eq("result_date", date);
    if (resultIds.error || !resultIds.data) {
      throw new AppError(503, "SIMULATION_DATA_UNAVAILABLE",
        "Unable to load simulation transactions.");
    }
    const selected = resultIds.data.filter((row) =>
      !input.breadCategoryId || row.bread_category_id === input.breadCategoryId);
    if (selected.length === 0) {
      return { date, page: input.page, pageSize: 50, total: 0, items: [] };
    }
    let query = supabaseAdmin.from("sales_transactions")
      .select("id, daily_result_id, sale_time, time_slot, quantity, unit_price, subtotal",
        { count: "exact" })
      .in("daily_result_id", selected.map((row) => row.id));
    if (input.timeSlot) query = query.eq("time_slot", input.timeSlot);
    const { data, count, error } = await query
      .order("sale_time", { ascending: true })
      .order("id", { ascending: true })
      .range((input.page - 1) * 50, input.page * 50 - 1);
    if (error || !data || count === null) {
      throw new AppError(503, "SIMULATION_DATA_UNAVAILABLE",
        "Unable to load simulation transactions.");
    }
    const categoryByResult = new Map(selected.map((row) => [row.id, row.bread_category_id]));
    return { date, page: input.page, pageSize: 50, total: count,
      items: data.map((row) => ({
        id: row.id, dailyResultId: row.daily_result_id,
        breadCategoryId: categoryByResult.get(row.daily_result_id),
        saleTime: row.sale_time, timeSlot: row.time_slot,
        quantity: number(row.quantity, "transaction quantity"),
        unitPrice: number(row.unit_price, "unit price"),
        subtotal: number(row.subtotal, "subtotal"),
        dataOrigin: "SIMULATION_GENERATED",
      })) };
  }
}
