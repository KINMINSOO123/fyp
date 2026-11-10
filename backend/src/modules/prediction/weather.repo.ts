import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import type { WeatherForecast } from "./open-weather-map.client.js";

export class WeatherRepo {
  async cache(actorUserId: string, targetDate: string,
    forecast: WeatherForecast): Promise<void> {
    const { error } = await supabaseAdmin.rpc("cache_next_day_weather", {
      p_actor_user_id: actorUserId, p_weather_date: targetDate,
      p_condition: forecast.condition, p_temp_high_c: forecast.tempHighC,
      p_temp_low_c: forecast.tempLowC,
      p_humidity_pct: forecast.humidityPct,
    });
    if (!error) return;
    if (error.code === "42501") throw new AppError(403, "FORBIDDEN",
      "Bakery Manager permission is required.");
    if (error.code === "PGRST202" || error.code === "42883") {
      throw new AppError(503, "WEATHER_SCHEMA_NOT_READY",
        "The weather cache migration is not available.");
    }
    throw new AppError(503, "WEATHER_CONTEXT_UNAVAILABLE",
      "Weather context could not be saved.");
  }
}
