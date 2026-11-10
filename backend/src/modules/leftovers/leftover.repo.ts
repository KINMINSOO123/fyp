import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

export interface LeftoverSummary {
  dailyResultId: string;
  date: string;
  breadCategoryId: string;
  breadCategoryName: string;
  produced: number;
  unitsSold: number;
  leftover: number;
  donated: number;
  wasted: number;
  remainingUnallocated: number;
  dataOrigin: "SIMULATION_GENERATED";
}

export interface CharityPartner {
  id: string;
  name: string;
  contactInfo: string | null;
  isActive: boolean;
}

function int(value: unknown, name: string): number {
  const parsed = Number(value);
  if (value === null || value === undefined ||
      !Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`Invalid stored ${name}.`);
  }
  return parsed;
}

function summary(row: Record<string, unknown>): LeftoverSummary {
  const result: LeftoverSummary = {
    dailyResultId: String(row.daily_result_id),
    date: String(row.result_date),
    breadCategoryId: String(row.bread_category_id),
    breadCategoryName: String(row.bread_category_name),
    produced: int(row.produced, "produced"),
    unitsSold: int(row.units_sold, "units sold"),
    leftover: int(row.leftover, "leftover"),
    donated: int(row.donated, "donated"),
    wasted: int(row.wasted, "wasted"),
    remainingUnallocated: int(row.remaining_unallocated_leftover, "remaining leftover"),
    dataOrigin: "SIMULATION_GENERATED",
  };
  if (result.leftover !== result.donated + result.wasted +
      result.remainingUnallocated) {
    throw new Error("The leftover allocation balance is inconsistent.");
  }
  return result;
}

export class LeftoverRepo {
  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new AppError(503, "BAKERY_SETTINGS_UNAVAILABLE",
        "Bakery timezone is unavailable.");
    }
    return data.timezone;
  }

  async list(date: string, categoryId: string | null): Promise<LeftoverSummary[]> {
    let query = supabaseAdmin.from("leftover_allocation_summary")
      .select("daily_result_id, result_date, bread_category_id, bread_category_name, produced, units_sold, leftover, donated, wasted, remaining_unallocated_leftover")
      .eq("result_date", date);
    if (categoryId) query = query.eq("bread_category_id", categoryId);
    const { data, error } = await query.order("bread_category_name", { ascending: true });
    if (error || !data) {
      throw new AppError(503, "LEFTOVER_SCHEMA_NOT_READY",
        "The leftover summary migration is unavailable.");
    }
    return data.map((row) => summary(row));
  }

  async find(resultId: string): Promise<LeftoverSummary> {
    const { data, error } = await supabaseAdmin.from("leftover_allocation_summary")
      .select("daily_result_id, result_date, bread_category_id, bread_category_name, produced, units_sold, leftover, donated, wasted, remaining_unallocated_leftover")
      .eq("daily_result_id", resultId).maybeSingle();
    if (error) throw new AppError(503, "LEFTOVER_SCHEMA_NOT_READY",
      "The leftover summary migration is unavailable.");
    if (!data) throw new AppError(404, "DAILY_RESULT_NOT_FOUND",
      "The completed daily result was not found.");
    return summary(data);
  }

  async listCharities(activeOnly: boolean): Promise<CharityPartner[]> {
    let query = supabaseAdmin.from("charity_partners")
      .select("id, name, contact_info, is_active");
    if (activeOnly) query = query.eq("is_active", true);
    const { data, error } = await query.order("name", { ascending: true });
    if (error || !data) throw new AppError(503, "CHARITY_DATA_UNAVAILABLE",
      "Unable to load charity partners.");
    return data.map((row) => ({
      id: row.id, name: row.name, contactInfo: row.contact_info,
      isActive: row.is_active,
    }));
  }

  async allocate(actorId: string, input: {
    action: "DONATE" | "WASTE"; dailyResultId: string;
    quantity: number; charityPartnerId: string | null;
    disposalReason: string | null; notes: string | null;
  }): Promise<unknown> {
    const { data, error } = await supabaseAdmin.rpc("allocate_leftover_with_audit", {
      p_actor_user_id: actorId, p_action: input.action,
      p_daily_result_id: input.dailyResultId, p_quantity: input.quantity,
      p_charity_partner_id: input.charityPartnerId,
      p_disposal_reason: input.disposalReason,
      p_notes: input.notes, p_confirm: true,
    });
    if (error) this.raise(error.code, error.message);
    return data;
  }

  async advanceStatus(actorId: string, donationId: string,
    status: "COLLECTED" | "COMPLETED"): Promise<unknown> {
    const { data, error } = await supabaseAdmin.rpc(
      "advance_donation_status_with_audit", {
        p_actor_user_id: actorId, p_donation_id: donationId,
        p_status: status, p_confirm: true,
      });
    if (error) this.raise(error.code, error.message);
    return data;
  }

  async saveCharity(actorId: string, input: {
    id: string | null; name: string; contactInfo: string | null;
    isActive: boolean;
  }): Promise<{ id: string }> {
    const { data, error } = await supabaseAdmin.rpc(
      "save_charity_partner_with_audit", {
        p_actor_user_id: actorId, p_partner_id: input.id,
        p_name: input.name, p_contact_info: input.contactInfo,
        p_is_active: input.isActive,
      });
    if (error) this.raise(error.code, error.message);
    if (typeof data !== "string") throw new Error("Invalid charity result.");
    return { id: data };
  }

  async listDonations(date: string, page: number) {
    const results = await supabaseAdmin.from("daily_results")
      .select("id, bread_category_id").eq("result_date", date);
    if (results.error || !results.data) throw new AppError(503,
      "DONATION_DATA_UNAVAILABLE", "Unable to load donations.");
    if (!results.data.length) return { date, page, pageSize: 50, total: 0, items: [] };
    const resultIds = results.data.map((row) => row.id);
    const { data, count, error } = await supabaseAdmin.from("donations")
      .select("id, daily_result_id, charity_partner_id, donation_date, quantity, status, notes, confirmed_by, charity_partners(name)",
        { count: "exact" })
      .in("daily_result_id", resultIds)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range((page - 1) * 50, page * 50 - 1);
    if (error || !data || count === null) throw new AppError(503,
      "DONATION_DATA_UNAVAILABLE", "Unable to load donations.");
    const categoryByResult = new Map(results.data.map((row) => [row.id, row.bread_category_id]));
    return { date, page, pageSize: 50, total: count,
      items: data.map((row) => ({
        id: row.id, dailyResultId: row.daily_result_id,
        breadCategoryId: categoryByResult.get(row.daily_result_id),
        charityPartnerId: row.charity_partner_id,
        charityPartnerName: (row.charity_partners as unknown as { name: string } | null)?.name ?? null,
        donationDate: row.donation_date,
        quantity: int(row.quantity, "donation quantity"),
        status: row.status, notes: row.notes,
        dataOrigin: "SIMULATION_GENERATED",
      })) };
  }

  private raise(code: string | undefined, message: string): never {
    if (code === "42501") throw new AppError(403, "FORBIDDEN", message);
    if (code === "22023") throw new AppError(400, "VALIDATION_ERROR", message);
    if (code === "P0002") throw new AppError(404, "NOT_FOUND", message);
    if (code === "P1002") throw new AppError(409, "CHARITY_INACTIVE", message);
    if (code === "P1003") throw new AppError(409, "ALLOCATION_CONFLICT", message);
    if (code === "P1004") throw new AppError(409, "ALLOCATION_DATA_INVALID", message);
    if (code === "23505") throw new AppError(409, "DUPLICATE_CHARITY", message);
    if (code === "PGRST202" || code === "42883") {
      throw new AppError(503, "LEFTOVER_SCHEMA_NOT_READY",
        "The leftover management migration is unavailable.");
    }
    throw new Error("Unable to save leftover management change.");
  }
}
