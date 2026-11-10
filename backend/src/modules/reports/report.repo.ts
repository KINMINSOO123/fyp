import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export interface StoredReportRow {
  dailyResultId: string;
  date: string;
  breadCategoryId: string;
  breadCategoryName: string;
  displayOrder: number;
  predictedUnitsSold: number;
  produced: number;
  unitsSold: number;
  lostSales: number;
  estimatedDemand: number;
  leftover: number;
  donated: number;
  wasted: number;
  remainingUnallocated: number;
  salesPredictionError: number;
  revenue: number;
  ingredientCost: number;
  grossProfit: number;
  evaluationUnitsSold: number | null;
  evaluationDataOrigin: "ACTUAL_TRANSACTION" | "IMPORTED_HISTORICAL" |
    "SIMULATION_GENERATED" | null;
}

function finite(value: unknown, field: string): number {
  const parsed = Number(value);
  if (value === null || value === undefined || !Number.isFinite(parsed)) {
    throw new Error(`Invalid stored ${field}.`);
  }
  return parsed;
}

function whole(value: unknown, field: string, signed = false): number {
  const parsed = finite(value, field);
  if (!Number.isSafeInteger(parsed) || (!signed && parsed < 0)) {
    throw new Error(`Invalid stored ${field}.`);
  }
  return parsed;
}

function money(value: unknown, field: string, signed = false): number {
  const parsed = finite(value, field);
  if ((!signed && parsed < 0) ||
      !Number.isSafeInteger(Math.round(parsed * 100)) ||
      Math.abs(parsed * 100 - Math.round(parsed * 100)) > 0.00001) {
    throw new Error(`Invalid stored ${field}.`);
  }
  return parsed;
}

function rowOf(row: Record<string, unknown>): StoredReportRow {
  const origin = row.evaluation_data_origin;
  if (origin !== null && origin !== "ACTUAL_TRANSACTION" &&
      origin !== "IMPORTED_HISTORICAL" && origin !== "SIMULATION_GENERATED") {
    throw new Error("Invalid stored history origin.");
  }
  const result: StoredReportRow = {
    dailyResultId: String(row.daily_result_id), date: String(row.result_date),
    breadCategoryId: String(row.bread_category_id),
    breadCategoryName: String(row.bread_category_name),
    displayOrder: whole(row.display_order, "category order"),
    predictedUnitsSold: whole(row.predicted_units_sold, "prediction"),
    produced: whole(row.produced, "production"),
    unitsSold: whole(row.units_sold, "sales"),
    lostSales: whole(row.lost_sales, "lost sales"),
    estimatedDemand: whole(row.estimated_demand, "estimated demand"),
    leftover: whole(row.leftover, "leftover"),
    donated: whole(row.donated, "donated"),
    wasted: whole(row.wasted, "wasted"),
    remainingUnallocated: whole(row.remaining_unallocated_leftover,
      "unallocated leftover"),
    salesPredictionError: whole(row.sales_prediction_error,
      "prediction error", true),
    revenue: money(row.revenue, "revenue"),
    ingredientCost: money(row.ingredient_cost, "ingredient cost"),
    grossProfit: money(row.gross_profit, "gross profit", true),
    evaluationUnitsSold: row.evaluation_units_sold === null ? null :
      whole(row.evaluation_units_sold, "evaluation sales"),
    evaluationDataOrigin: origin,
  };
  if (result.leftover !== result.produced - result.unitsSold ||
      result.estimatedDemand !== result.unitsSold + result.lostSales ||
      result.leftover !== result.donated + result.wasted +
        result.remainingUnallocated ||
      result.salesPredictionError !== result.unitsSold -
        result.predictedUnitsSold ||
      Math.round(result.grossProfit * 100) !==
        Math.round(result.revenue * 100) -
        Math.round(result.ingredientCost * 100) ||
      (result.evaluationUnitsSold === null) !==
        (result.evaluationDataOrigin === null)) {
    throw new Error("Stored report totals are inconsistent.");
  }
  return result;
}

export class ReportRepo {
  async categories(): Promise<Array<{ id: string; name: string; isActive: boolean }>> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id,name,is_active").order("display_order", { ascending: true });
    if (error || !data) throw new AppError(503, "REPORT_CATEGORIES_UNAVAILABLE",
      "Unable to load report categories.");
    return data.map((row) => ({ id: row.id, name: row.name,
      isActive: row.is_active }));
  }

  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new AppError(503, "BAKERY_SETTINGS_UNAVAILABLE",
        "Bakery timezone is unavailable.");
    }
    return data.timezone;
  }

  async list(fromDate: string, toDate: string, breadCategoryId: string | null):
    Promise<StoredReportRow[]> {
    const rows: StoredReportRow[] = [];
    const pageSize = 500;
    for (let offset = 0; ; offset += pageSize) {
      let query = supabaseAdmin.from("report_result_summary").select(
        "daily_result_id,result_date,bread_category_id,bread_category_name,display_order,predicted_units_sold,produced,units_sold,lost_sales,estimated_demand,leftover,donated,wasted,remaining_unallocated_leftover,sales_prediction_error,revenue,ingredient_cost,gross_profit,evaluation_units_sold,evaluation_data_origin")
        .gte("result_date", fromDate).lte("result_date", toDate);
      if (breadCategoryId) query = query.eq("bread_category_id", breadCategoryId);
      const { data, error } = await query
        .order("result_date", { ascending: true })
        .order("display_order", { ascending: true })
        .order("daily_result_id", { ascending: true })
        .range(offset, offset + pageSize - 1);
      if (error || !data) throw new AppError(503, "REPORT_SCHEMA_NOT_READY",
        "The report summary migration is unavailable.");
      rows.push(...data.map((row) => rowOf(row)));
      if (data.length < pageSize) return rows;
    }
  }
}
