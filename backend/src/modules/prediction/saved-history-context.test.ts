import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { SelectedSalesObservation } from "./history-selection.service.js";
import { attachSavedHistoryContexts } from "./saved-history-context.js";

const category = "00000000-0000-4000-8000-000000000001";
const day = "2026-11-05";
const simulation: SelectedSalesObservation = {
  id: "00000000-0000-4000-8000-000000000002",
  breadCategoryId: category, salesDate: day, unitsSold: 12,
  dataOrigin: "SIMULATION_GENERATED", sourceDailyResultId: "result-1",
  externalSourceReference: null,
};
const result = { id: "result-1", result_date: day,
  bread_category_id: category, prediction_id: "prediction-1" };
const prediction = { id: "prediction-1", target_date: day,
  bread_category_id: category, context_snapshot: { factors: {
    weekdayFactor: 1.1, monsoonFactor: 1, weatherFactor: 0.95,
    holidayFactor: 1.05,
  } } };

test("T-DP-HCTX-01 [FR-DP-01]: linked daily prediction supplies saved context", () => {
  const [row] = attachSavedHistoryContexts([simulation], [result], [prediction]);
  assert.deepEqual(row?.contextFactors, prediction.context_snapshot.factors);
});

test("T-DP-HCTX-02 [FR-DP-01]: result and prediction must match date and category", () => {
  for (const changed of [
    { results: [{ ...result, result_date: "2026-11-04" }], predictions: [prediction] },
    { results: [{ ...result, bread_category_id: "other" }], predictions: [prediction] },
    { results: [result], predictions: [{ ...prediction, target_date: "2026-11-04" }] },
    { results: [result], predictions: [{ ...prediction, bread_category_id: "other" }] },
    { results: [], predictions: [prediction] },
  ]) {
    assert.throws(() => attachSavedHistoryContexts([simulation],
      changed.results, changed.predictions), (error: unknown) =>
      error instanceof AppError &&
      error.code === "HISTORICAL_CONTEXT_RELATION_INVALID");
  }
});

test("T-DP-HCTX-03 [FR-DP-01]: absent context defaults; malformed context fails", () => {
  const imported: SelectedSalesObservation = { ...simulation,
    id: "import-1", dataOrigin: "IMPORTED_HISTORICAL",
    sourceDailyResultId: null, externalSourceReference: "import-1" };
  assert.equal(attachSavedHistoryContexts([imported], [], [])[0]
    ?.contextFactors, null);
  assert.equal(attachSavedHistoryContexts([simulation], [result],
    [{ ...prediction, context_snapshot: {} }])[0]?.contextFactors, null);
  for (const bad of ["bad", { factors: null }, { factors: {
    ...prediction.context_snapshot.factors, weatherFactor: -1 } },
  { factors: { ...prediction.context_snapshot.factors, extra: 1 } }]) {
    assert.throws(() => attachSavedHistoryContexts([simulation], [result],
      [{ ...prediction, context_snapshot: bad }]), (error: unknown) =>
      error instanceof AppError && error.code === "HISTORICAL_CONTEXT_INVALID");
  }
});
