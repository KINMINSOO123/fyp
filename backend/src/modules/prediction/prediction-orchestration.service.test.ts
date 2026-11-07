import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { FastApiMlClient, PredictionResultDto } from "./fast-api-ml.client.js";
import type { PredictionHistoryService } from "./prediction-history.service.js";
import { PredictionOrchestrationService } from "./prediction-orchestration.service.js";
import type { PredictionRepo, PredictionToSave } from "./prediction.repo.js";

const first = "00000000-0000-4000-8000-000000000001";
const second = "00000000-0000-4000-8000-000000000002";
const activeId = "00000000-0000-4000-8000-000000000003";
const actor = "00000000-0000-4000-8000-000000000004";
const date = "2026-11-05";
const rules = {
  baseQuantities: { [second]: 10 },
  weekdayFactors: { SUNDAY: 1, MONDAY: 1, TUESDAY: 1,
    WEDNESDAY: 1, THURSDAY: 1.2, FRIDAY: 1, SATURDAY: 1 },
  monsoonMonths: [11, 12], monsoonFactor: 1.1, otherSeasonFactor: 1,
  weatherFactors: { CLEAR: 1, CLOUDY: 1, RAIN: 0.9, STORM: 0.8,
    OTHER: 1 },
  weatherFallbackFactor: null,
  holidayFactor: 1.3, nonHolidayFactor: 1,
  calendarVerifiedThrough: null, allowCalendarFallback: false,
};

function repo(): Pick<PredictionRepo,
  "getBakeryTimezone" | "listActiveCategories" | "listActiveModels" |
  "getContextData" | "hasPredictionForDate" | "saveBatch" | "listByDate"> {
  return {
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async listActiveCategories() { return [
      { id: first, name: "White Bread", displayOrder: 1 },
      { id: second, name: "Wholemeal Bread", displayOrder: 2 },
    ]; },
    async listActiveModels() { return [{ id: activeId, breadCategoryId: first,
      modelType: "RANDOM_FOREST", lifecycleStatus: "ACTIVE",
      artifactKey: "models/active.joblib" }]; },
    async getContextData() { return {
      confidenceThreshold: 75, rules,
      weather: { id: "00000000-0000-4000-8000-000000000005",
        condition: "RAIN" as const },
      calendarEvents: [{ id: "00000000-0000-4000-8000-000000000006",
        eventType: "PUBLIC_HOLIDAY" as const }],
    }; },
    async hasPredictionForDate() { return false; },
    async saveBatch(_actor, _date, items) { return items.map((item, index) => ({
      id: `00000000-0000-4000-8000-${(index + 7).toString().padStart(12, "0")}`,
      breadCategoryId: item.breadCategoryId,
    })); },
    async listByDate() { return []; },
  };
}

function history(): Pick<PredictionHistoryService, "loadSelected"> {
  return { async loadSelected(categoryId) {
    const observations = categoryId === first
      ? Array.from({ length: 30 }, (_, index) => ({
        id: `00000000-0000-4000-8000-${(index + 100).toString().padStart(12, "0")}`,
        breadCategoryId: categoryId,
        salesDate: new Date(Date.UTC(2026, 9, 1 + index))
          .toISOString().slice(0, 10),
        unitsSold: index,
        dataOrigin: "SIMULATION_GENERATED" as const,
        sourceDailyResultId: `00000000-0000-4000-8000-${(index + 200).toString().padStart(12, "0")}`,
        externalSourceReference: null,
      })) : [];
    return { observations, distinctDayCount: observations.length, rejected: [] };
  } };
}

test("T-DP-GEN-01 [FR-DP-05, FR-DP-07, FR-DP-08, NFR-ACC-08]: saves model and cold-start predictions together", async () => {
  const data = repo();
  let saved: PredictionToSave[] = [];
  data.saveBatch = async (actorId, targetDate, items) => {
    assert.equal(actorId, actor);
    assert.equal(targetDate, date);
    saved = items;
    return items.map((item, index) => ({
      id: `00000000-0000-4000-8000-${(index + 7).toString().padStart(12, "0")}`,
      breadCategoryId: item.breadCategoryId,
    }));
  };
  const ml: Pick<FastApiMlClient, "predictCategory"> = {
    async predictCategory(input): Promise<PredictionResultDto> {
      assert.equal(input.targetDate, date);
      assert.deepEqual(input.factors, { weekdayFactor: 1.2,
        monsoonFactor: 1.1, weatherFactor: 0.9, holidayFactor: 1.3 });
      if (input.breadCategoryId === first) {
        assert.equal(input.observations.length, 30);
        assert.equal(input.activeModel?.modelVersionId, activeId);
        return { breadCategoryId: first, targetDate: date,
          predictionMode: "MODEL", predictedUnitsSold: 20,
          modelVersionId: activeId, confidence: 74.9,
          lowConfidence: true, confidenceLabel: "Low Confidence",
          reason: "MODEL_READY" };
      }
      assert.equal(input.configuredBaseQuantity, 10);
      return { breadCategoryId: second, targetDate: date,
        predictionMode: "COLD_START", predictedUnitsSold: 15,
        modelVersionId: null, confidence: null,
        lowConfidence: true, confidenceLabel: "Low-confidence heuristic estimate",
        reason: "INSUFFICIENT_HISTORY", baseDemand: 10,
        baseSource: "CONFIGURED_BASE" };
    },
  };
  const service = new PredictionOrchestrationService(data, history(), ml,
    () => new Date("2026-11-04T03:00:00Z"));
  const result = await service.generate(actor, {});
  assert.equal(result.predictions.length, 2);
  assert.equal(saved[0]?.result.predictionMode, "MODEL");
  assert.equal(saved[1]?.result.confidence, null);
  assert.equal(saved[0]?.contextSnapshot.weatherSource, "STORED_RECORD");
  assert.equal(saved[0]?.contextSnapshot.calendarSource, "STORED_EVENTS");
});

test("T-DP-GEN-02 [FR-DP-05, NFR-REL-01]: duplicate and invalid requests stop before inference", async () => {
  const data = repo();
  let mlCalls = 0;
  data.hasPredictionForDate = async () => true;
  const service = new PredictionOrchestrationService(data, history(), {
    async predictCategory() { mlCalls += 1; throw new Error("Must not run."); },
  }, () => new Date("2026-11-04T03:00:00Z"));
  await assert.rejects(service.generate(actor, {}),
    (error: unknown) => error instanceof AppError &&
      error.code === "PREDICTION_ALREADY_EXISTS");
  await assert.rejects(service.generate(actor, { targetDate: "2026-11-06" }),
    (error: unknown) => error instanceof AppError &&
      error.code === "INVALID_PREDICTION_DATE");
  await assert.rejects(service.generate(actor, { role: "BAKERY_MANAGER" }),
    (error: unknown) => error instanceof AppError &&
      error.code === "VALIDATION_ERROR");
  assert.equal(mlCalls, 0);
});

test("T-DP-GEN-03 [FR-DP-04, NFR-REL-03]: missing weather requires an explicit fallback", async () => {
  const data = repo();
  data.getContextData = async () => ({
    confidenceThreshold: 75, rules,
    weather: null, calendarEvents: [],
  });
  let saved = false;
  data.saveBatch = async () => { saved = true; return []; };
  const service = new PredictionOrchestrationService(data, history(), {
    async predictCategory() { throw new Error("Must not run."); },
  }, () => new Date("2026-11-04T03:00:00Z"));
  await assert.rejects(service.generate(actor, {}),
    (error: unknown) => error instanceof AppError &&
      error.code === "WEATHER_CONTEXT_UNAVAILABLE");
  assert.equal(saved, false);
});

test("T-DP-GEN-05 [FR-DP-08, NFR-REL-01]: one failed category prevents every prediction write", async () => {
  const data = repo();
  let saved = false;
  data.saveBatch = async () => { saved = true; return []; };
  const service = new PredictionOrchestrationService(data, history(), {
    async predictCategory(input) {
      if (input.breadCategoryId === second) {
        throw new AppError(503, "ML_UNAVAILABLE", "Prediction service unavailable.");
      }
      return { breadCategoryId: first, targetDate: date,
        predictionMode: "MODEL" as const, predictedUnitsSold: 20,
        modelVersionId: activeId, confidence: 80,
        lowConfidence: false, confidenceLabel: "Model agreement",
        reason: "MODEL_READY" as const };
    },
  }, () => new Date("2026-11-04T03:00:00Z"));
  await assert.rejects(service.generate(actor, {}),
    (error: unknown) => error instanceof AppError &&
      error.code === "ML_UNAVAILABLE");
  assert.equal(saved, false);
});

test("T-DP-GEN-06 [FR-DP-07]: absent history needs that category's configured base", async () => {
  const data = repo();
  data.getContextData = async () => ({
    confidenceThreshold: 75,
    rules: { ...rules, baseQuantities: {} },
    weather: { id: "00000000-0000-4000-8000-000000000005",
      condition: "RAIN" as const },
    calendarEvents: [{ id: "00000000-0000-4000-8000-000000000006",
      eventType: "PUBLIC_HOLIDAY" as const }],
  });
  const service = new PredictionOrchestrationService(data, history(), {
    async predictCategory() { throw new Error("Must not run."); },
  }, () => new Date("2026-11-04T03:00:00Z"));
  await assert.rejects(service.generate(actor, {}),
    (error: unknown) => error instanceof AppError &&
      error.code === "PREDICTION_CONFIG_INCOMPLETE");
});

test("T-DP-GEN-08 [FR-DP-05, FR-DP-08]: next-day read uses bakery timezone", async () => {
  const data = repo();
  let requested = "";
  data.listByDate = async (targetDate) => {
    requested = targetDate;
    return [];
  };
  const service = new PredictionOrchestrationService(data, history(), undefined,
    () => new Date("2026-11-04T17:00:00Z"));
  const state = await service.getNextDayState();
  assert.equal(state.targetDate, "2026-11-06");
  assert.equal(requested, "2026-11-06");
});
