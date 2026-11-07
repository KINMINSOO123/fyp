import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import type { PredictionResultDto } from "./fast-api-ml.client.js";
import type {
  CalendarEventType, WeatherCondition,
} from "./prediction-context.js";

export interface ActiveBreadCategory {
  id: string;
  name: string;
  displayOrder: number;
}

export interface PredictionModelReference {
  id: string;
  breadCategoryId: string;
  modelType: string;
  lifecycleStatus: string;
  artifactKey: string;
}

export interface PredictionContextData {
  confidenceThreshold: unknown;
  rules: unknown;
  weather: { id: string; condition: WeatherCondition } | null;
  calendarEvents: Array<{ id: string; eventType: CalendarEventType }>;
}

export interface PredictionToSave {
  breadCategoryId: string;
  result: PredictionResultDto;
  weatherRecordId: string | null;
  calendarEventIds: string[];
  contextSnapshot: Record<string, unknown>;
}

export interface StoredPrediction {
  id: string;
  targetDate: string;
  breadCategoryId: string;
  breadCategoryName: string;
  predictedUnitsSold: number;
  predictionMode: "MODEL" | "COLD_START";
  confidence: number | null;
  modelVersionId: string | null;
  weatherRecordId: string | null;
  contextSnapshot: Record<string, unknown> | null;
  createdAt: string;
}

interface PredictionDbRow {
  id: string;
  target_date: string;
  bread_category_id: string;
  bread_categories: { name: string };
  predicted_units_sold: number;
  prediction_mode: "MODEL" | "COLD_START";
  confidence: number | string | null;
  model_version_id: string | null;
  weather_record_id: string | null;
  context_snapshot: Record<string, unknown> | null;
  created_at: string;
}

function mapPrediction(row: PredictionDbRow): StoredPrediction {
  return {
    id: row.id,
    targetDate: row.target_date,
    breadCategoryId: row.bread_category_id,
    breadCategoryName: row.bread_categories.name,
    predictedUnitsSold: row.predicted_units_sold,
    predictionMode: row.prediction_mode,
    confidence: row.confidence === null ? null : Number(row.confidence),
    modelVersionId: row.model_version_id,
    weatherRecordId: row.weather_record_id,
    contextSnapshot: row.context_snapshot,
    createdAt: row.created_at,
  };
}

export class PredictionRepo {
  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new AppError(409, "PREDICTION_CONFIG_INCOMPLETE",
        "Bakery timezone is not configured.");
    }
    return data.timezone;
  }

  async listActiveCategories(): Promise<ActiveBreadCategory[]> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id, name, display_order").eq("is_active", true)
      .order("display_order", { ascending: true });
    if (error || !data) throw new Error("Unable to load active bread categories.");
    return data.map((row) => ({ id: row.id, name: row.name,
      displayOrder: row.display_order }));
  }

  async listActiveModels(): Promise<PredictionModelReference[]> {
    const { data, error } = await supabaseAdmin.from("ml_model_versions")
      .select("id, bread_category_id, model_type, lifecycle_status, artifact_key")
      .eq("lifecycle_status", "ACTIVE");
    if (error || !data) throw new Error("Unable to load active models.");
    return data.map((row) => ({ id: row.id,
      breadCategoryId: row.bread_category_id, modelType: row.model_type,
      lifecycleStatus: row.lifecycle_status, artifactKey: row.artifact_key }));
  }

  async getContextData(targetDate: string): Promise<PredictionContextData> {
    const [settings, weather, events] = await Promise.all([
      supabaseAdmin.from("system_settings")
        .select("setting_key, setting_value")
        .in("setting_key", ["prediction.low_confidence_threshold",
          "prediction.context_rules"]),
      supabaseAdmin.from("weather_records")
        .select("id, condition").eq("weather_date", targetDate).maybeSingle(),
      supabaseAdmin.from("calendar_events")
        .select("id, event_type").eq("event_date", targetDate)
        .order("id", { ascending: true }),
    ]);
    if (settings.error || weather.error || events.error ||
        !settings.data || !events.data) {
      throw new Error("Unable to load prediction context.");
    }
    const byKey = new Map(settings.data.map((row) =>
      [row.setting_key, row.setting_value]));
    return {
      confidenceThreshold: byKey.get("prediction.low_confidence_threshold"),
      rules: byKey.get("prediction.context_rules"),
      weather: weather.data ? {
        id: weather.data.id,
        condition: weather.data.condition as WeatherCondition,
      } : null,
      calendarEvents: events.data.map((row) => ({ id: row.id,
        eventType: row.event_type as CalendarEventType })),
    };
  }

  async hasPredictionForDate(targetDate: string): Promise<boolean> {
    const { data, error } = await supabaseAdmin.from("daily_predictions")
      .select("id").eq("target_date", targetDate).limit(1);
    if (error || !data) throw new Error("Unable to check stored predictions.");
    return data.length > 0;
  }

  async saveBatch(actorUserId: string, targetDate: string,
    items: PredictionToSave[]): Promise<Array<{ id: string; breadCategoryId: string }>> {
    const { data, error } = await supabaseAdmin.rpc(
      "save_daily_predictions_batch_with_audit", {
        p_actor_user_id: actorUserId,
        p_target_date: targetDate,
        p_predictions: items.map((item) => ({
          breadCategoryId: item.breadCategoryId,
          predictedUnitsSold: item.result.predictedUnitsSold,
          predictionMode: item.result.predictionMode,
          confidence: item.result.confidence,
          modelVersionId: item.result.modelVersionId,
          weatherRecordId: item.weatherRecordId,
          calendarEventIds: item.calendarEventIds,
          contextSnapshot: item.contextSnapshot,
        })),
      },
    );
    if (error || !Array.isArray(data)) {
      if (error?.code === "42501") {
        throw new AppError(403, "FORBIDDEN", "Bakery Manager permission is required.");
      }
      if (error?.code === "P0001" || error?.code === "23505") {
        throw new AppError(409, "PREDICTION_ALREADY_EXISTS",
          "Predictions for this date already exist.");
      }
      if (error?.code === "22023") {
        throw new AppError(409, "PREDICTION_STATE_CHANGED",
          "Prediction inputs changed; refresh and try again.");
      }
      if (error?.code === "PGRST202" || error?.code === "42703") {
        throw new AppError(503, "PREDICTION_SCHEMA_NOT_READY",
          "The prediction persistence migration is not available.");
      }
      throw new Error("Unable to save the predictions.");
    }
    if (data.length !== items.length) {
      throw new Error("Prediction persistence returned an incomplete result.");
    }
    const ids = new Set(items.map((item) => item.breadCategoryId));
    const result = data as Array<{ id: string; bread_category_id: string }>;
    if (result.some((row) => typeof row.id !== "string" ||
        !ids.delete(row.bread_category_id)) || ids.size) {
      throw new Error("Prediction persistence returned a mismatched category.");
    }
    return result.map((row) => ({ id: row.id,
      breadCategoryId: row.bread_category_id }));
  }

  async listByDate(targetDate: string): Promise<StoredPrediction[]> {
    const { data, error } = await supabaseAdmin.from("daily_predictions")
      .select(`id, target_date, bread_category_id, predicted_units_sold,
        prediction_mode, confidence, model_version_id, weather_record_id,
        context_snapshot, created_at, bread_categories(name)`)
      .eq("target_date", targetDate).order("bread_category_id", { ascending: true });
    if (error?.code === "42703") {
      throw new AppError(503, "PREDICTION_SCHEMA_NOT_READY",
        "The prediction context migration is not available.");
    }
    if (error || !data) throw new Error("Unable to load stored predictions.");
    return (data as unknown as PredictionDbRow[]).map(mapPrediction);
  }
}
