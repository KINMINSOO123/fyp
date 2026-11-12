import { supabaseAdmin } from "../../config/supabase.js";
import {
  isCalendarDate,
  type DailySalesObservationRow,
  type SelectedSalesObservation,
} from "./history-selection.service.js";
import { attachSavedHistoryContexts } from "./saved-history-context.js";

const pageSize = 500;

interface DailySalesDbRow {
  id: string;
  bread_category_id: string;
  sales_date: string;
  units_sold: number;
  data_origin: string;
  is_validated: boolean;
  source_daily_result_id: string | null;
  external_source_reference: string | null;
}

export class DailySalesRecordRepo {
  async withSavedContexts(observations: SelectedSalesObservation[]):
    Promise<SelectedSalesObservation[]> {
    const ids = [...new Set(observations.flatMap((row) =>
      row.sourceDailyResultId ? [row.sourceDailyResultId] : []))];
    if (!ids.length) return observations.map((row) => ({ ...row,
      contextFactors: null }));
    const results = await supabaseAdmin.from("daily_results")
      .select("id,result_date,bread_category_id,prediction_id").in("id", ids);
    if (results.error || !results.data) throw new Error(
      "Unable to load historical daily results.");
    const predictionIds = [...new Set(results.data.map((row) => row.prediction_id))];
    if (!predictionIds.length) {
      return attachSavedHistoryContexts(observations, results.data, []);
    }
    const predictions = await supabaseAdmin.from("daily_predictions")
      .select("id,target_date,bread_category_id,context_snapshot")
      .in("id", predictionIds);
    if (predictions.error || !predictions.data) throw new Error(
      "Unable to load historical prediction context.");
    return attachSavedHistoryContexts(observations, results.data,
      predictions.data);
  }
  // Node is the only database reader. FastAPI receives the selected DTO later.
  async listBeforeDate(
    breadCategoryId: string,
    targetDate: string,
  ): Promise<DailySalesObservationRow[]> {
    if (!breadCategoryId.trim() || !isCalendarDate(targetDate)) {
      throw new Error("A category and valid target date are required.");
    }

    const observations: DailySalesObservationRow[] = [];
    let offset = 0;

    while (true) {
      const { data, error } = await supabaseAdmin
        .from("daily_sales_records")
        .select(
          "id, bread_category_id, sales_date, units_sold, data_origin, is_validated, source_daily_result_id, external_source_reference",
        )
        .eq("bread_category_id", breadCategoryId)
        .lt("sales_date", targetDate)
        .order("sales_date", { ascending: true })
        .order("id", { ascending: true })
        .range(offset, offset + pageSize - 1);

      if (error || data === null) {
        throw new Error("Unable to load daily sales history.");
      }

      for (const value of data) {
        const row = value as DailySalesDbRow;
        observations.push({
          id: row.id,
          breadCategoryId: row.bread_category_id,
          salesDate: row.sales_date,
          unitsSold: row.units_sold,
          dataOrigin: row.data_origin,
          isValidated: row.is_validated,
          sourceDailyResultId: row.source_daily_result_id,
          externalSourceReference: row.external_source_reference,
        });
      }

      if (data.length < pageSize) {
        break;
      }
      offset += pageSize;
    }

    return observations;
  }
}
