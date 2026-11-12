import { AppError } from "../../shared/AppError.js";
import type { SelectedSalesObservation } from "./history-selection.service.js";

export interface HistoricalResultSource {
  id: string;
  result_date: string;
  bread_category_id: string;
  prediction_id: string;
}

export interface HistoricalPredictionSource {
  id: string;
  target_date: string;
  bread_category_id: string;
  context_snapshot: unknown;
}

const factorKeys = ["weekdayFactor", "monsoonFactor", "weatherFactor",
  "holidayFactor"] as const;

function invalidSnapshot(): never {
  throw new AppError(409, "HISTORICAL_CONTEXT_INVALID",
    "A linked prediction has invalid saved context factors.");
}

export function attachSavedHistoryContexts(
  observations: SelectedSalesObservation[],
  results: HistoricalResultSource[],
  predictions: HistoricalPredictionSource[],
): SelectedSalesObservation[] {
  const byResult = new Map(results.map((row) => [row.id, row]));
  const byPrediction = new Map(predictions.map((row) => [row.id, row]));
  return observations.map((row) => {
    if (!row.sourceDailyResultId) return { ...row, contextFactors: null };
    const result = byResult.get(row.sourceDailyResultId);
    const prediction = result ? byPrediction.get(result.prediction_id) : null;
    if (!result || !prediction || result.result_date !== row.salesDate ||
        result.bread_category_id !== row.breadCategoryId ||
        prediction.target_date !== row.salesDate ||
        prediction.bread_category_id !== row.breadCategoryId) {
      throw new AppError(409, "HISTORICAL_CONTEXT_RELATION_INVALID",
        "A sales record has a mismatched result or prediction source.");
    }
    const snapshot = prediction.context_snapshot;
    if (snapshot === null) return { ...row, contextFactors: null };
    if (typeof snapshot !== "object" || Array.isArray(snapshot)) {
      invalidSnapshot();
    }
    const saved = snapshot as Record<string, unknown>;
    if (!("factors" in saved)) return { ...row, contextFactors: null };
    const factors = saved.factors;
    if (!factors || typeof factors !== "object" || Array.isArray(factors)) {
      invalidSnapshot();
    }
    const entries = factors as Record<string, unknown>;
    if (Object.keys(entries).length !== factorKeys.length ||
        factorKeys.some((key) => typeof entries[key] !== "number" ||
          !Number.isFinite(entries[key]) || (entries[key] as number) < 0)) {
      invalidSnapshot();
    }
    return { ...row, contextFactors: {
      weekdayFactor: entries.weekdayFactor as number,
      monsoonFactor: entries.monsoonFactor as number,
      weatherFactor: entries.weatherFactor as number,
      holidayFactor: entries.holidayFactor as number,
    } };
  });
}
