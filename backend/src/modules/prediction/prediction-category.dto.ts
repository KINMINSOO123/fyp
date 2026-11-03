import {
  isCalendarDate,
  type HistorySelectionResult,
  type SelectedSalesObservation,
} from "./history-selection.service.js";

export interface ColdStartFactorsDto {
  weekdayFactor: number;
  monsoonFactor: number;
  weatherFactor: number;
  holidayFactor: number;
}

export interface ActiveModelDto {
  modelVersionId: string;
  breadCategoryId: string;
  modelType: string;
  lifecycleStatus: string;
  artifactKey: string;
}

export interface PredictionCategoryInputDto {
  contractVersion: 1;
  breadCategoryId: string;
  targetDate: string;
  observations: SelectedSalesObservation[];
  configuredBaseQuantity: number | null;
  factors: ColdStartFactorsDto;
  confidenceThreshold: number;
  activeModel: ActiveModelDto | null;
}

export interface PredictionCategoryConfig {
  breadCategoryId: string;
  targetDate: string;
  configuredBaseQuantity: number | null;
  factors: ColdStartFactorsDto;
  confidenceThreshold: number;
  activeModel: ActiveModelDto | null;
}

function nonnegativeFinite(value: number): boolean {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

export function buildPredictionCategoryInput(
  history: HistorySelectionResult,
  config: PredictionCategoryConfig,
): PredictionCategoryInputDto {
  if (!config.breadCategoryId.trim() || !isCalendarDate(config.targetDate)) {
    throw new Error("A category and valid target date are required.");
  }
  if (history.distinctDayCount !== history.observations.length) {
    throw new Error("Selected history count does not match observations.");
  }
  const dates = new Set<string>();
  for (const observation of history.observations) {
    if (
      observation.breadCategoryId !== config.breadCategoryId ||
      !isCalendarDate(observation.salesDate) ||
      observation.salesDate >= config.targetDate ||
      dates.has(observation.salesDate)
    ) {
      throw new Error("Selected history has a category or date mismatch.");
    }
    dates.add(observation.salesDate);
  }

  if (
    config.configuredBaseQuantity !== null &&
    !nonnegativeFinite(config.configuredBaseQuantity)
  ) {
    throw new Error("Configured base quantity must be nonnegative and finite.");
  }
  if (history.observations.length === 0 && config.configuredBaseQuantity === null) {
    throw new Error("A configured base quantity is required without history.");
  }
  if (
    !nonnegativeFinite(config.confidenceThreshold) ||
    config.confidenceThreshold > 100
  ) {
    throw new Error("Confidence threshold must be between 0 and 100.");
  }
  for (const factor of Object.values(config.factors)) {
    if (!nonnegativeFinite(factor)) {
      throw new Error("Cold-start factors must be nonnegative and finite.");
    }
  }

  return {
    contractVersion: 1,
    breadCategoryId: config.breadCategoryId,
    targetDate: config.targetDate,
    observations: history.observations.map((observation) => ({ ...observation })),
    configuredBaseQuantity: config.configuredBaseQuantity,
    factors: { ...config.factors },
    confidenceThreshold: config.confidenceThreshold,
    activeModel: config.activeModel === null ? null : { ...config.activeModel },
  };
}
