import { AppError } from "../../shared/AppError.js";
import { buildPredictionCategoryInput } from "./prediction-category.dto.js";
import type { FastApiMlClient } from "./fast-api-ml.client.js";
import { isCalendarDate } from "./history-selection.service.js";
import { parsePredictionRules, resolvePredictionContext } from "./prediction-context.js";
import type { PredictionHistoryService } from "./prediction-history.service.js";
import type { PredictionRepo } from "./prediction.repo.js";

type DataRepo = Pick<PredictionRepo,
  "getBakeryTimezone" | "listActiveCategories" | "listActiveModels" |
  "getContextData" | "hasPredictionForDate" | "saveBatch" | "listByDate">;
type HistoryReader = Pick<PredictionHistoryService, "loadSelected">;
type MlAdapter = Pick<FastApiMlClient, "predictCategory">;

function tomorrowInBakery(now: Date, timezone: string): string {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(now);
  } catch {
    throw new AppError(409, "PREDICTION_CONFIG_INCOMPLETE",
      "Bakery timezone is invalid.");
  }
  const read = (type: string) => parts.find((part) => part.type === type)?.value;
  const today = `${read("year")}-${read("month")}-${read("day")}`;
  const next = new Date(`${today}T00:00:00.000Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString().slice(0, 10);
}

export class PredictionOrchestrationService {
  constructor(
    private readonly providedRepo?: DataRepo,
    private readonly providedHistory?: HistoryReader,
    private readonly providedMl?: MlAdapter,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private async repo(): Promise<DataRepo> {
    return this.providedRepo ?? new (
      await import("./prediction.repo.js")
    ).PredictionRepo();
  }

  private async history(): Promise<HistoryReader> {
    return this.providedHistory ?? new (
      await import("./prediction-history.service.js")
    ).PredictionHistoryService();
  }

  private async ml(): Promise<MlAdapter> {
    return this.providedMl ?? (
      await import("./fast-api-ml.client.js")
    ).FastApiMlClient.fromEnvironment();
  }

  async generate(actorUserId: string, body: unknown) {
    if (body !== undefined && (typeof body !== "object" || body === null ||
        Array.isArray(body) || Object.keys(body).some((key) => key !== "targetDate"))) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Only an optional targetDate is accepted.");
    }
    const requested = body && typeof body === "object" &&
      "targetDate" in body ? body.targetDate : undefined;
    if (requested !== undefined &&
        (typeof requested !== "string" || !isCalendarDate(requested))) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid targetDate is required.");
    }
    const repo = await this.repo();
    const targetDate = tomorrowInBakery(this.now(),
      await repo.getBakeryTimezone());
    if (requested !== undefined && requested !== targetDate) {
      throw new AppError(400, "INVALID_PREDICTION_DATE",
        "Generate predictions for the next bakery date.");
    }
    const [categories, activeModels, context, alreadyStored] = await Promise.all([
      repo.listActiveCategories(), repo.listActiveModels(),
      repo.getContextData(targetDate), repo.hasPredictionForDate(targetDate),
    ]);
    if (alreadyStored) {
      throw new AppError(409, "PREDICTION_ALREADY_EXISTS",
        "Predictions for the next bakery date already exist.");
    }
    if (categories.length === 0) {
      throw new AppError(409, "NO_ACTIVE_CATEGORIES",
        "Ask the System Administrator to configure an active bread category.");
    }
    const threshold = context.confidenceThreshold;
    if (typeof threshold !== "number" || !Number.isFinite(threshold) ||
        threshold < 0 || threshold > 100) {
      throw new AppError(409, "PREDICTION_CONFIG_INCOMPLETE",
        "The model confidence threshold is not configured.");
    }
    const rules = parsePredictionRules(context.rules);
    const resolved = resolvePredictionContext(
      targetDate, rules, context.weather, context.calendarEvents,
    );
    const modelsByCategory = new Map(activeModels.map((model) =>
      [model.breadCategoryId, model]));
    const historyReader = await this.history();
    const histories = await Promise.all(categories.map((category) =>
      historyReader.loadSelected(category.id, targetDate)));
    const inputs = categories.map((category, index) => {
      const selected = histories[index];
      if (!selected) throw new Error("Selected history is missing.");
      const active = modelsByCategory.get(category.id);
      const configuredBaseQuantity = rules.baseQuantities[category.id] ?? null;
      if (selected.distinctDayCount === 0 && configuredBaseQuantity === null) {
        throw new AppError(409, "PREDICTION_CONFIG_INCOMPLETE",
          `A cold-start base quantity is required for ${category.name}.`);
      }
      return buildPredictionCategoryInput(selected, {
        breadCategoryId: category.id,
        targetDate,
        configuredBaseQuantity,
        factors: resolved.factors,
        confidenceThreshold: threshold,
        activeModel: active ? {
          modelVersionId: active.id,
          breadCategoryId: category.id,
          modelType: active.modelType,
          lifecycleStatus: active.lifecycleStatus,
          artifactKey: active.artifactKey,
        } : null,
      });
    });
    const ml = await this.ml();
    const predictions = await Promise.all(inputs.map((input) =>
      ml.predictCategory(input)));
    const items = predictions.map((result, index) => {
      const category = categories[index]!;
      const history = histories[index]!;
      return {
        breadCategoryId: category.id,
        result,
        weatherRecordId: resolved.weatherRecordId,
        calendarEventIds: resolved.calendarEventIds,
        contextSnapshot: {
          contractVersion: 1,
          factors: resolved.factors,
          confidenceThreshold: threshold,
          weatherSource: resolved.weatherSource,
          weatherCondition: context.weather?.condition ?? null,
          calendarSource: resolved.calendarSource,
          calendarEventIds: resolved.calendarEventIds,
          selectedHistoryDayCount: history.distinctDayCount,
          reason: result.reason,
          lowConfidence: result.lowConfidence,
          confidenceLabel: result.confidenceLabel,
          ...(result.predictionMode === "COLD_START" ? {
            baseDemand: result.baseDemand, baseSource: result.baseSource,
          } : {}),
        },
      };
    });
    const saved = await repo.saveBatch(actorUserId, targetDate, items);
    const idByCategory = new Map(saved.map((row) => [row.breadCategoryId, row.id]));
    return { targetDate, predictions: items.map((item, index) => ({
      id: idByCategory.get(item.breadCategoryId),
      breadCategoryName: categories[index]!.name,
      ...item.result,
      context: item.contextSnapshot,
    })) };
  }

  async listByDate(targetDate: string) {
    if (!isCalendarDate(targetDate)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid prediction date is required.");
    }
    return (await this.repo()).listByDate(targetDate);
  }

  async getNextDayState() {
    const repo = await this.repo();
    const targetDate = tomorrowInBakery(this.now(),
      await repo.getBakeryTimezone());
    return { targetDate, predictions: await repo.listByDate(targetDate) };
  }
}
