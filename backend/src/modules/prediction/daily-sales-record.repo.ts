import { supabaseAdmin } from "../../config/supabase.js";
import {
  isCalendarDate,
  type DailySalesObservationRow,
} from "./history-selection.service.js";

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
