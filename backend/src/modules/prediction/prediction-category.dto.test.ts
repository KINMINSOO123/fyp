import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildPredictionCategoryInput,
  type PredictionCategoryConfig,
} from "./prediction-category.dto.js";
import type { HistorySelectionResult } from "./history-selection.service.js";

const categoryId = "00000000-0000-4000-8000-000000000001";
const config: PredictionCategoryConfig = {
  breadCategoryId: categoryId,
  targetDate: "2026-11-04",
  configuredBaseQuantity: null,
  factors: {
    weekdayFactor: 1,
    monsoonFactor: 1.1,
    weatherFactor: 0.9,
    holidayFactor: 1,
  },
  confidenceThreshold: 75,
  activeModel: null,
};
const history: HistorySelectionResult = {
  distinctDayCount: 1,
  rejected: [],
  observations: [{
    id: "00000000-0000-4000-8000-000000000003",
    breadCategoryId: categoryId,
    salesDate: "2026-11-03",
    unitsSold: 0,
    dataOrigin: "SIMULATION_GENERATED",
    sourceDailyResultId: "00000000-0000-4000-8000-000000000002",
    externalSourceReference: null,
  }],
};

test("T-DP-DTO-07 [FR-DP-01, BR-DP-04]: maps selected sales to versioned ML DTO", () => {
  const dto = buildPredictionCategoryInput(history, config);
  assert.equal(dto.contractVersion, 1);
  assert.equal(dto.observations[0]?.unitsSold, 0);
  assert.equal(dto.observations[0]?.dataOrigin, "SIMULATION_GENERATED");
  assert.equal(dto.observations[0]?.sourceDailyResultId,
    "00000000-0000-4000-8000-000000000002");
  assert.equal(dto.configuredBaseQuantity, null);
  assert.equal(dto.confidenceThreshold, 75);
});

test("T-DP-DTO-08 [FR-DP-07]: no history requires configured base", () => {
  const empty = { observations: [], rejected: [], distinctDayCount: 0 };
  assert.throws(() => buildPredictionCategoryInput(empty, config), /base quantity/);
  const dto = buildPredictionCategoryInput(empty, {
    ...config,
    configuredBaseQuantity: 20,
  });
  assert.equal(dto.configuredBaseQuantity, 20);
});

test("T-DP-DTO-09 [FR-DP-01, BR-DP-02]: mismatched or invalid inputs are rejected", () => {
  assert.throws(() => buildPredictionCategoryInput({
    ...history,
    distinctDayCount: 2,
  }, config), /count/);
  assert.throws(() => buildPredictionCategoryInput(history, {
    ...config,
    confidenceThreshold: 101,
  }), /threshold/);
  assert.throws(() => buildPredictionCategoryInput(history, {
    ...config,
    factors: { ...config.factors, weatherFactor: Number.NaN },
  }), /factors/);
});
