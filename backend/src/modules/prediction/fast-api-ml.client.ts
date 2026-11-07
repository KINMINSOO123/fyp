import { AppError } from "../../shared/AppError.js";
import type {
  ColdStartFactorsDto,
  PredictionCategoryInputDto,
} from "./prediction-category.dto.js";
import {
  isEvaluationResponse,
  type EvaluationInputDto,
  type EvaluationResponseDto,
} from "./model-evaluation.dto.js";

export interface ColdStartPredictionDto {
  breadCategoryId: string;
  targetDate: string;
  predictionMode: "COLD_START";
  predictedUnitsSold: number;
  modelVersionId: null;
  confidence: null;
  lowConfidence: true;
  confidenceLabel: string;
  reason:
    | "INSUFFICIENT_HISTORY"
    | "NO_ACTIVE_MODEL"
    | "INVALID_ACTIVE_MODEL"
    | "ARTIFACT_UNAVAILABLE";
  baseDemand: number;
  baseSource: "OBSERVATION_MEAN" | "CONFIGURED_BASE";
}

export interface ModelPredictionDto {
  breadCategoryId: string;
  targetDate: string;
  predictionMode: "MODEL";
  predictedUnitsSold: number;
  modelVersionId: string;
  confidence: number;
  lowConfidence: boolean;
  confidenceLabel: string;
  reason: "MODEL_READY";
}

export type PredictionResultDto = ColdStartPredictionDto | ModelPredictionDto;

export interface TrainingCandidateInputDto {
  contractVersion: 1;
  breadCategoryId: string;
  rfModelVersionId: string;
  lrModelVersionId: string;
  holdoutStart: string;
  observations: Array<PredictionCategoryInputDto["observations"][number] & {
    contextFactors?: ColdStartFactorsDto | null;
  }>;
}

export interface TrainingCandidateResponseDto {
  breadCategoryId: string;
  trainingStart: string;
  trainingEnd: string;
  holdoutStart: string;
  fitSampleCount: number;
  holdoutSampleCount: number;
  historicalContextDefaultCount: number;
  featureVersion: number;
  trainingFingerprint: string;
  trainingOrigins: Record<"ACTUAL_TRANSACTION" | "IMPORTED_HISTORICAL" | "SIMULATION_GENERATED", number>;
  holdoutOrigins: Record<"ACTUAL_TRANSACTION" | "IMPORTED_HISTORICAL" | "SIMULATION_GENERATED", number>;
  candidates: Array<{
    modelVersionId: string;
    modelType: "RANDOM_FOREST" | "LINEAR_REGRESSION";
    artifactKey: string;
    sha256: string;
  }>;
}

export interface ArtifactValidationInputDto {
  contractVersion: 1;
  modelVersionId: string;
  breadCategoryId: string;
  lifecycleStatus: "CANDIDATE" | "INACTIVE";
  artifactKey: string;
  artifactSha256: string;
}

export interface ArtifactValidationResponseDto {
  modelVersionId: string;
  breadCategoryId: string;
  valid: boolean;
  trainingEnd: string | null;
  featureVersion: number | null;
}

type MlFetch = typeof fetch;

interface MlClientOptions {
  baseUrl: string;
  internalToken: string;
  timeoutMs?: number;
  fetcher?: MlFetch;
}

const reasons = new Set([
  "INSUFFICIENT_HISTORY", "NO_ACTIVE_MODEL", "INVALID_ACTIVE_MODEL",
  "ARTIFACT_UNAVAILABLE",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isColdStartResponse(
  value: unknown,
  request: PredictionCategoryInputDto,
): value is ColdStartPredictionDto {
  if (!isRecord(value)) return false;
  return value.breadCategoryId === request.breadCategoryId &&
    value.targetDate === request.targetDate &&
    value.predictionMode === "COLD_START" &&
    Number.isSafeInteger(value.predictedUnitsSold) &&
    (value.predictedUnitsSold as number) >= 0 &&
    value.modelVersionId === null &&
    value.confidence === null &&
    value.lowConfidence === true &&
    typeof value.confidenceLabel === "string" &&
    value.confidenceLabel.length > 0 &&
    reasons.has(value.reason as string) &&
    typeof value.baseDemand === "number" &&
    Number.isFinite(value.baseDemand) &&
    value.baseDemand >= 0 &&
    (value.baseSource === "OBSERVATION_MEAN" ||
      value.baseSource === "CONFIGURED_BASE");
}

function isModelResponse(
  value: unknown,
  request: PredictionCategoryInputDto,
): value is ModelPredictionDto {
  if (!isRecord(value) || request.activeModel === null) return false;
  return value.breadCategoryId === request.breadCategoryId &&
    value.targetDate === request.targetDate &&
    value.predictionMode === "MODEL" &&
    Number.isSafeInteger(value.predictedUnitsSold) &&
    (value.predictedUnitsSold as number) >= 0 &&
    value.modelVersionId === request.activeModel.modelVersionId &&
    typeof value.confidence === "number" &&
    Number.isFinite(value.confidence) &&
    value.confidence >= 0 && value.confidence <= 100 &&
    value.lowConfidence === (value.confidence < request.confidenceThreshold) &&
    typeof value.confidenceLabel === "string" &&
    value.confidenceLabel.length > 0 &&
    value.reason === "MODEL_READY";
}

function isTrainingResponse(
  value: unknown,
  request: TrainingCandidateInputDto,
): value is TrainingCandidateResponseDto {
  if (!isRecord(value) || !Array.isArray(value.candidates) ||
      value.candidates.length !== 2) return false;
  const candidates = value.candidates;
  const expected: Array<[string, string]> = [
    ["RANDOM_FOREST", request.rfModelVersionId],
    ["LINEAR_REGRESSION", request.lrModelVersionId],
  ];
  const validOrigins = (counts: unknown): boolean =>
    isRecord(counts) && [
      "ACTUAL_TRANSACTION", "IMPORTED_HISTORICAL", "SIMULATION_GENERATED",
    ].every((origin) => Number.isSafeInteger(counts[origin]) &&
      (counts[origin] as number) >= 0);
  const ordered = [...request.observations].sort(
    (a, b) => a.salesDate.localeCompare(b.salesDate),
  );
  const before = ordered.filter((item) => item.salesDate < request.holdoutStart);
  const after = ordered.filter((item) => item.salesDate >= request.holdoutStart);
  const exactOrigins = (counts: unknown, observations: typeof ordered): boolean =>
    validOrigins(counts) && [
      "ACTUAL_TRANSACTION", "IMPORTED_HISTORICAL", "SIMULATION_GENERATED",
    ].every((origin) => (counts as Record<string, number>)[origin] ===
      observations.filter((item) => item.dataOrigin === origin).length);
  return value.breadCategoryId === request.breadCategoryId &&
    before.length >= 2 && after.length >= 1 &&
    value.trainingStart === before[0]?.salesDate &&
    value.trainingEnd === before[before.length - 1]?.salesDate &&
    value.holdoutStart === request.holdoutStart &&
    value.fitSampleCount === before.length - 1 &&
    value.holdoutSampleCount === after.length &&
    value.historicalContextDefaultCount === ordered.slice(1).filter(
      (item) => item.contextFactors == null,
    ).length &&
    value.featureVersion === 1 &&
    typeof value.trainingFingerprint === "string" &&
    /^[0-9a-f]{64}$/.test(value.trainingFingerprint) &&
    exactOrigins(value.trainingOrigins, before) &&
    exactOrigins(value.holdoutOrigins, after) &&
    candidates.every((item: unknown, index: number) =>
      isRecord(item) && item.modelType === expected[index]?.[0] &&
      item.modelVersionId === expected[index]?.[1] &&
      typeof item.artifactKey === "string" && item.artifactKey.length > 0 &&
      typeof item.sha256 === "string" && /^[0-9a-f]{64}$/.test(item.sha256));
}

export class FastApiMlClient {
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly timeoutMs: number;
  private readonly fetcher: MlFetch;

  constructor(options: MlClientOptions) {
    if (!options.internalToken.trim()) {
      throw new Error("ML_INTERNAL_TOKEN is required.");
    }
    const base = new URL(options.baseUrl);
    if (base.protocol !== "https:" &&
        !(base.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(base.hostname))) {
      throw new Error("The ML service must use HTTPS outside the local machine.");
    }
    if (!Number.isSafeInteger(options.timeoutMs ?? 15000) ||
        (options.timeoutMs ?? 15000) <= 0) {
      throw new Error("ML timeout must be a positive whole number.");
    }
    this.baseUrl = `${base.toString().replace(/\/$/, "")}/`;
    this.token = options.internalToken;
    this.timeoutMs = options.timeoutMs ?? 15000;
    this.fetcher = options.fetcher ?? fetch;
  }

  static fromEnvironment(): FastApiMlClient {
    return new FastApiMlClient({
      baseUrl: process.env.ML_SERVICE_URL ?? "http://127.0.0.1:8000",
      internalToken: process.env.ML_INTERNAL_TOKEN ?? "",
    });
  }

  async predictCategory(
    request: PredictionCategoryInputDto,
  ): Promise<PredictionResultDto> {
    const body = await this.postJson("predict", request);
    if (!isColdStartResponse(body, request) && !isModelResponse(body, request)) {
      throw new AppError(502, "ML_CONTRACT_ERROR",
        "The prediction service returned an invalid response.");
    }
    return body;
  }

  async trainCandidates(
    request: TrainingCandidateInputDto,
  ): Promise<TrainingCandidateResponseDto> {
    const body = await this.postJson("train", request, 120000);
    if (!isTrainingResponse(body, request)) {
      throw new AppError(502, "ML_CONTRACT_ERROR",
        "The prediction service returned an invalid training response.");
    }
    return body;
  }

  async evaluateModels(
    request: EvaluationInputDto,
  ): Promise<EvaluationResponseDto> {
    const body = await this.postJson("evaluate", request, 120000);
    if (!isEvaluationResponse(body, request)) {
      throw new AppError(502, "ML_CONTRACT_ERROR",
        "The prediction service returned an invalid evaluation response.");
    }
    return body;
  }

  async validateModelArtifact(
    request: ArtifactValidationInputDto,
  ): Promise<ArtifactValidationResponseDto> {
    const body = await this.postJson("artifacts/validate", request);
    if (!isRecord(body) ||
        body.modelVersionId !== request.modelVersionId ||
        body.breadCategoryId !== request.breadCategoryId ||
        typeof body.valid !== "boolean" ||
        (body.valid === true && (
          typeof body.trainingEnd !== "string" ||
          body.featureVersion !== 1
        )) ||
        (body.valid === false && (
          body.trainingEnd !== null || body.featureVersion !== null
        ))) {
      throw new AppError(502, "ML_CONTRACT_ERROR",
        "The prediction service returned an invalid artifact check.");
    }
    return body as unknown as ArtifactValidationResponseDto;
  }

  private async postJson(
    path: string,
    payload: unknown,
    timeoutMs = this.timeoutMs,
  ): Promise<unknown> {
    let response: Response;
    try {
      response = await this.fetcher(new URL(path, this.baseUrl), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-ML-Internal-Token": this.token,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new AppError(503, "ML_UNAVAILABLE", "The prediction service is unavailable.");
    }

    if (!response.ok) {
      let remoteCode: unknown;
      try {
        const errorBody: unknown = await response.json();
        remoteCode = isRecord(errorBody) && isRecord(errorBody.detail)
          ? errorBody.detail.code : undefined;
      } catch { /* An invalid error body is still a failed ML request. */ }
      if (response.status === 503 && remoteCode === "MODEL_INFERENCE_NOT_READY") {
        throw new AppError(503, "MODEL_INFERENCE_NOT_READY",
          "Model inference is not available yet.");
      }
      if (response.status === 409 && remoteCode === "CANDIDATE_ALREADY_EXISTS") {
        throw new AppError(409, "CANDIDATE_ALREADY_EXISTS",
          "The candidate artifact already exists.");
      }
      if (response.status === 422) {
        throw new AppError(502, "ML_CONTRACT_ERROR",
          "The prediction service rejected the internal request.");
      }
      throw new AppError(503, "ML_UNAVAILABLE", "The prediction service is unavailable.");
    }

    try {
      return await response.json() as unknown;
    } catch {
      throw new AppError(502, "ML_CONTRACT_ERROR",
        "The prediction service returned an invalid response.");
    }
  }
}
