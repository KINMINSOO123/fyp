import { supabaseAdmin } from "../../config/supabase.js";
import type { ExistingSale, ImportCategory, SaleToInsert } from
  "./adapted-demo-import.js";

const pageSize = 500;

export class AdaptedDemoImportRepo {
  async loadCategories(): Promise<ImportCategory[]> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id, name, is_active").order("display_order", { ascending: true });
    if (error || !data) throw new Error("Unable to read the bread catalogue.");
    return data.map((row) => ({ id: row.id, name: row.name,
      isActive: row.is_active }));
  }

  async loadExistingSales(): Promise<ExistingSale[]> {
    const result: ExistingSale[] = [];
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await supabaseAdmin.from("daily_sales_records")
        .select("id, bread_category_id, sales_date, units_sold, data_origin, is_validated, source_daily_result_id, external_source_reference")
        .order("sales_date", { ascending: true })
        .order("id", { ascending: true })
        .range(offset, offset + pageSize - 1);
      if (error || !data) throw new Error("Unable to read existing sales history.");
      result.push(...data.map((row) => ({ id: row.id,
        breadCategoryId: row.bread_category_id, salesDate: row.sales_date,
        unitsSold: row.units_sold, dataOrigin: row.data_origin,
        isValidated: row.is_validated,
        sourceDailyResultId: row.source_daily_result_id,
        externalSourceReference: row.external_source_reference })));
      if (data.length < pageSize) return result;
    }
  }

  async getBakeryDate(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new Error("Unable to read the bakery timezone.");
    }
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: data.timezone, year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date());
    const get = (type: string) => parts.find((part) => part.type === type)?.value;
    return `${get("year")}-${get("month")}-${get("day")}`;
  }

  async insertAccepted(rows: SaleToInsert[]): Promise<number> {
    if (!rows.length) return 0;
    // One PostgREST insert request: no upsert and no conflict-ignore policy.
    // PostgreSQL uniqueness constraints reject concurrent duplicate writes.
    const { data, error } = await supabaseAdmin.from("daily_sales_records")
      .insert(rows).select("id");
    if (error || !data || data.length !== rows.length) {
      throw new Error(error ?
        `The import was rejected: ${error.code ?? "DB_ERROR"}: ${error.message}` :
        "The database returned an incomplete import result.");
    }
    return data.length;
  }
}
