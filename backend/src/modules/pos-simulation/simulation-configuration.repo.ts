import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";

function mutationError(error: { code: string; message: string } | null): never {
  if (error?.code === "42501") throw new AppError(403, "FORBIDDEN",
    "Administrator permission is required.");
  if (error?.code === "22023") throw new AppError(400, "VALIDATION_ERROR",
    error.message);
  if (error?.code === "P1005") throw new AppError(409,
    "SIMULATION_SETUP_REQUIRED", error.message);
  if (["PGRST202", "PGRST205", "42883", "42P01", "42703"].includes(error?.code ?? "")) {
    throw new AppError(503, "SIMULATION_SCHEMA_NOT_READY",
      "Apply the independent-demand simulation migration.");
  }
  throw new Error("Unable to save simulation configuration.");
}

export class SimulationConfigurationRepo {
  async get() {
    const [categories, baselines, scenario] = await Promise.all([
      supabaseAdmin.from("bread_categories")
        .select("id,name,display_order").eq("is_active", true)
        .order("display_order"),
      supabaseAdmin.from("simulation_baselines")
        .select("bread_category_id,base_demand,baseline_source,imported_sample_count,imported_first_date,imported_last_date,imported_fingerprint,configured_at"),
      supabaseAdmin.from("simulation_scenarios")
        .select("scenario_version,weekday_factors,weather_factors,holiday_factor,non_holiday_factor,variation_max_pct,updated_at")
        .eq("singleton_guard", true).maybeSingle(),
    ]);
    if (["42P01", "PGRST205"].includes(baselines.error?.code ?? "") ||
        ["42P01", "PGRST205"].includes(scenario.error?.code ?? "")) {
      throw new AppError(503, "SIMULATION_SCHEMA_NOT_READY",
        "Apply the independent-demand simulation migration.");
    }
    if (categories.error || baselines.error || scenario.error ||
        !categories.data || !baselines.data || !scenario.data) {
      throw new Error("Unable to load simulation configuration.");
    }
    const byCategory = new Map(baselines.data.map((row) =>
      [row.bread_category_id, row]));
    return {
      categories: categories.data.map((category) => ({
        id: category.id, name: category.name,
        displayOrder: category.display_order,
        baseline: byCategory.has(category.id) ? (() => {
          const row = byCategory.get(category.id)!;
          return { baseDemand: Number(row.base_demand),
            source: row.baseline_source,
            importedSampleCount: row.imported_sample_count,
            importedFirstDate: row.imported_first_date,
            importedLastDate: row.imported_last_date,
            importedFingerprint: row.imported_fingerprint,
            configuredAt: row.configured_at };
        })() : null,
      })),
      scenario: {
        scenarioVersion: scenario.data.scenario_version,
        weekdayFactors: scenario.data.weekday_factors,
        weatherFactors: scenario.data.weather_factors,
        holidayFactor: Number(scenario.data.holiday_factor),
        nonHolidayFactor: Number(scenario.data.non_holiday_factor),
        variationMaxPct: Number(scenario.data.variation_max_pct),
        updatedAt: scenario.data.updated_at,
      },
    };
  }

  async saveBaseline(actor: string, categoryId: string,
    source: string, baseDemand: number | null) {
    const { data, error } = await supabaseAdmin.rpc("set_simulation_baseline", {
      p_actor_user_id: actor, p_category_id: categoryId,
      p_source: source, p_manual_base: baseDemand,
    });
    if (error || !data) mutationError(error);
    return data;
  }

  async saveScenario(actor: string, value: {
    weekdayFactors: Record<string, number>;
    weatherFactors: Record<string, number>;
    holidayFactor: number;
    nonHolidayFactor: number;
    variationMaxPct: number;
  }) {
    const { data, error } = await supabaseAdmin.rpc("update_simulation_scenario", {
      p_actor_user_id: actor, p_weekday_factors: value.weekdayFactors,
      p_weather_factors: value.weatherFactors,
      p_holiday_factor: value.holidayFactor,
      p_non_holiday_factor: value.nonHolidayFactor,
      p_variation_max_pct: value.variationMaxPct,
    });
    if (error || !data) mutationError(error);
    return data;
  }
}
