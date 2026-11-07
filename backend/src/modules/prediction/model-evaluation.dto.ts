import type { TrainingCandidateInputDto } from "./fast-api-ml.client.js";

type Observation = TrainingCandidateInputDto["observations"][number];
type ModelType = "RANDOM_FOREST" | "LINEAR_REGRESSION";
type EvaluationRole = "CANDIDATE_RF" | "BASELINE_LR" | "CURRENT_ACTIVE_RF";
type DataOrigin = "ACTUAL_TRANSACTION" | "IMPORTED_HISTORICAL" | "SIMULATION_GENERATED";

export interface EvaluationInputDto {
  contractVersion: 1;
  breadCategoryId: string;
  holdoutStart: string;
  observations: Observation[];
  models: Array<{
    role: EvaluationRole;
    modelVersionId: string;
    modelType: ModelType;
    artifactKey: string;
  }>;
}

export interface EvaluationResponseDto {
  breadCategoryId: string;
  holdoutStart: string;
  holdoutEnd: string;
  holdoutManifest: Record<string, unknown>;
  holdoutFingerprint: string;
  dataOrigins: DataOrigin[];
  evaluationLabel: "ACTUAL_ONLY" | "IMPORTED_HISTORICAL_ONLY" |
    "SIMULATION_BASED" | "MIXED_NON_SIMULATION";
  originCounts: Record<DataOrigin, number>;
  results: Array<{
    role: EvaluationRole;
    modelVersionId: string;
    modelType: ModelType;
    mae: number;
    rmse: number;
    mape: number | null;
    rSquared: number | null;
    sampleCount: number;
    mapeSampleCount: number;
    mapeUnavailableReason: "NO_NONZERO_ACTUALS" | null;
    rSquaredUnavailableReason: "INSUFFICIENT_SAMPLES" | "CONSTANT_ACTUALS" | null;
    predictions: Array<{ salesDate: string; predictedUnitsSold: number }>;
  }>;
}

const origins: DataOrigin[] = [
  "ACTUAL_TRANSACTION", "IMPORTED_HISTORICAL", "SIMULATION_GENERATED",
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function sameArray(a: unknown, b: unknown[]): boolean {
  return Array.isArray(a) && a.length === b.length &&
    a.every((item, index) => item === b[index]);
}

function close(a: unknown, b: number): boolean {
  return typeof a === "number" && Number.isFinite(a) &&
    Math.abs(a - b) <= 1e-8 * Math.max(1, Math.abs(a), Math.abs(b));
}

function validManifest(
  value: unknown,
  request: EvaluationInputDto,
  earlier: Observation[],
  holdout: Observation[],
): value is Record<string, unknown> {
  if (!isRecord(value) || value.breadCategoryId !== request.breadCategoryId ||
      value.holdoutStart !== request.holdoutStart || value.featureVersion !== 1 ||
      typeof value.featureHistoryFingerprint !== "string" ||
      !/^[0-9a-f]{64}$/.test(value.featureHistoryFingerprint) ||
      !sameArray(value.priorObservationIds, earlier.map((row) => row.id)) ||
      !Array.isArray(value.holdoutRows) ||
      value.holdoutRows.length !== holdout.length) return false;
  return value.holdoutRows.every((raw: unknown, index: number) => {
    const expected = holdout[index];
    if (!isRecord(raw) || !expected) return false;
    const actualContext = raw.contextFactors;
    const expectedContext = expected.contextFactors ?? null;
    const contextMatches = expectedContext === null
      ? actualContext === null
      : isRecord(actualContext) &&
        actualContext.weekdayFactor === expectedContext.weekdayFactor &&
        actualContext.monsoonFactor === expectedContext.monsoonFactor &&
        actualContext.weatherFactor === expectedContext.weatherFactor &&
        actualContext.holidayFactor === expectedContext.holidayFactor;
    return raw.id === expected.id &&
      raw.breadCategoryId === expected.breadCategoryId &&
      raw.salesDate === expected.salesDate &&
      raw.unitsSold === expected.unitsSold &&
      raw.dataOrigin === expected.dataOrigin &&
      raw.sourceDailyResultId === expected.sourceDailyResultId &&
      raw.externalSourceReference === expected.externalSourceReference &&
      contextMatches;
  });
}

function validMetrics(
  result: Record<string, unknown>,
  holdout: Observation[],
): boolean {
  if (!Array.isArray(result.predictions) ||
      result.predictions.length !== holdout.length ||
      result.sampleCount !== holdout.length) return false;
  const predicted: number[] = [];
  for (let index = 0; index < holdout.length; index++) {
    const row = result.predictions[index];
    if (!isRecord(row) || row.salesDate !== holdout[index]?.salesDate ||
        !Number.isSafeInteger(row.predictedUnitsSold) ||
        (row.predictedUnitsSold as number) < 0) return false;
    predicted.push(row.predictedUnitsSold as number);
  }
  const actual = holdout.map((row) => row.unitsSold);
  const errors = actual.map((value, index) => value - (predicted[index] ?? 0));
  const mae = errors.reduce((sum, error) => sum + Math.abs(error), 0) / actual.length;
  const squared = errors.reduce((sum, error) => sum + error * error, 0);
  const rmse = Math.sqrt(squared / actual.length);
  const positive = actual.map((value, index) => ({ value, error: errors[index] ?? 0 }))
    .filter((row) => row.value > 0);
  const mape = positive.length > 0
    ? 100 * positive.reduce((sum, row) => sum + Math.abs(row.error) / row.value, 0) /
      positive.length
    : null;
  const mean = actual.reduce((sum, value) => sum + value, 0) / actual.length;
  const variance = actual.reduce((sum, value) => sum + (value - mean) ** 2, 0);
  const rSquared = actual.length >= 2 && variance > 0 ? 1 - squared / variance : null;
  return close(result.mae, mae) && close(result.rmse, rmse) &&
    (result.rmse as number) + 1e-8 >= (result.mae as number) &&
    result.mapeSampleCount === positive.length &&
    (mape === null ? result.mape === null : close(result.mape, mape)) &&
    (rSquared === null ? result.rSquared === null : close(result.rSquared, rSquared)) &&
    result.mapeUnavailableReason === (mape === null ? "NO_NONZERO_ACTUALS" : null) &&
    result.rSquaredUnavailableReason === (rSquared !== null ? null :
      actual.length < 2 ? "INSUFFICIENT_SAMPLES" : "CONSTANT_ACTUALS");
}

export function isEvaluationResponse(
  value: unknown,
  request: EvaluationInputDto,
): value is EvaluationResponseDto {
  if (!isRecord(value) || !Array.isArray(value.results) ||
      !Array.isArray(value.dataOrigins) || !isRecord(value.originCounts) ||
      typeof value.holdoutFingerprint !== "string" ||
      !/^[0-9a-f]{64}$/.test(value.holdoutFingerprint)) return false;
  const ordered = [...request.observations].sort(
    (a, b) => a.salesDate.localeCompare(b.salesDate),
  );
  const earlier = ordered.filter((row) => row.salesDate < request.holdoutStart);
  const holdout = ordered.filter((row) => row.salesDate >= request.holdoutStart);
  if (earlier.length === 0 || holdout.length === 0 ||
      value.breadCategoryId !== request.breadCategoryId ||
      value.holdoutStart !== request.holdoutStart ||
      value.holdoutEnd !== holdout[holdout.length - 1]?.salesDate ||
      !validManifest(value.holdoutManifest, request, earlier, holdout)) return false;
  const usedOrigins = origins.filter((origin) => holdout.some(
    (row) => row.dataOrigin === origin,
  ));
  if (!sameArray(value.dataOrigins, usedOrigins) ||
      origins.some((origin) => (value.originCounts as Record<string, unknown>)[origin] !== holdout.filter(
        (row) => row.dataOrigin === origin,
      ).length)) return false;
  const label = usedOrigins.includes("SIMULATION_GENERATED") ? "SIMULATION_BASED" :
    usedOrigins.length === 1 && usedOrigins[0] === "ACTUAL_TRANSACTION" ? "ACTUAL_ONLY" :
    usedOrigins.length === 1 && usedOrigins[0] === "IMPORTED_HISTORICAL" ? "IMPORTED_HISTORICAL_ONLY" :
    "MIXED_NON_SIMULATION";
  if (value.evaluationLabel !== label || value.results.length !== request.models.length) {
    return false;
  }
  const returnedRoles = new Set<string>();
  return value.results.every((raw: unknown) => {
    if (!isRecord(raw) || typeof raw.role !== "string" ||
        returnedRoles.has(raw.role)) return false;
    returnedRoles.add(raw.role);
    const expected = request.models.find((model) => model.role === raw.role);
    return expected !== undefined &&
      raw.modelVersionId === expected.modelVersionId &&
      raw.modelType === expected.modelType &&
      validMetrics(raw, holdout);
  });
}
