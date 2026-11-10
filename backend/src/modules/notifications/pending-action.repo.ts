import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export type PendingSnapshot = {
  activeCategoryIds: string[];
  todayPredictionIds: string[];
  nextPredictionIds: string[];
  confirmedCategoryIds: string[];
  completedCategoryIds: string[];
  remainingLeftovers: number;
};

export class PendingActionRepo {
  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new AppError(503, "BAKERY_SETTINGS_UNAVAILABLE",
        "Bakery timezone is unavailable.");
    }
    return data.timezone;
  }

  async snapshot(date: string, nextDate: string): Promise<PendingSnapshot> {
    const [categories, todayPredictions, nextPredictions, decisions,
      results, leftovers] = await Promise.all([
      supabaseAdmin.from("bread_categories").select("id")
        .eq("is_active", true),
      supabaseAdmin.from("daily_predictions").select("bread_category_id")
        .eq("target_date", date),
      supabaseAdmin.from("daily_predictions").select("bread_category_id")
        .eq("target_date", nextDate),
      supabaseAdmin.from("production_decisions").select("bread_category_id")
        .eq("target_date", date),
      supabaseAdmin.from("daily_results").select("bread_category_id")
        .eq("result_date", date),
      supabaseAdmin.from("leftover_allocation_summary")
        .select("bread_category_id,remaining_unallocated_leftover")
        .eq("result_date", date),
    ]);
    if ([categories, todayPredictions, nextPredictions, decisions,
      results, leftovers].some((item) => item.error || !item.data)) {
      throw new AppError(503, "PENDING_STATE_UNAVAILABLE",
        "Unable to load the current workflow state.");
    }
    return {
      activeCategoryIds: (categories.data ?? []).map((row) => row.id),
      todayPredictionIds: (todayPredictions.data ?? [])
        .map((row) => row.bread_category_id),
      nextPredictionIds: (nextPredictions.data ?? [])
        .map((row) => row.bread_category_id),
      confirmedCategoryIds: (decisions.data ?? [])
        .map((row) => row.bread_category_id),
      completedCategoryIds: (results.data ?? [])
        .map((row) => row.bread_category_id),
      remainingLeftovers: (leftovers.data ?? []).reduce((total, row) => {
        const quantity = Number(row.remaining_unallocated_leftover);
        if (!Number.isSafeInteger(quantity) || quantity < 0) {
          throw new Error("Invalid stored leftover balance.");
        }
        return total + quantity;
      }, 0),
    };
  }
}
