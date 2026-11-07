import { randomUUID } from "node:crypto";
import { AppError } from "../../shared/AppError.js";
import type { FastApiMlClient } from "./fast-api-ml.client.js";
import type { EvaluationInputDto } from "./model-evaluation.dto.js";
import type { ModelManagementRepo, StoredModelVersion } from "./model-management.repo.js";
import type { PredictionHistoryService } from "./prediction-history.service.js";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ModelRepo = Pick<ModelManagementRepo,
  "assertStorageReady" | "listTrainingCategories" | "listModelReviews" | "findModelReviewById" |
  "getBakeryTimezone" | "isActiveCategory" | "findModelById" |
  "findBaseline" | "findActive" | "findEvaluationById" | "findComparableEvaluation" |
  "hasValidEvaluation" | "createCandidates" | "recordEvaluations" |
  "activateCandidate" | "restorePreviousModel">;
type HistoryReader = Pick<PredictionHistoryService, "loadSelected">;
type MlAdapter = Pick<FastApiMlClient,
  "trainCandidates" | "evaluateModels" | "validateModelArtifact">;

function bakeryDate(now: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const read = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${read("year")}-${read("month")}-${read("day")}`;
}

export class ModelManagementService {
  constructor(
    private readonly providedRepo?: ModelRepo,
    private readonly providedHistory?: HistoryReader,
    private readonly providedMl?: MlAdapter,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private async repo(): Promise<ModelRepo> {
    return this.providedRepo ?? new (
      await import("./model-management.repo.js")
    ).ModelManagementRepo();
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

  private async assertValidArtifact(model: StoredModelVersion): Promise<void> {
    if (!model.artifactSha256 ||
        (model.lifecycleStatus !== "CANDIDATE" &&
         model.lifecycleStatus !== "INACTIVE")) {
      throw new AppError(409, "MODEL_ARTIFACT_INVALID",
        "The selected model artifact cannot be verified.");
    }
    const artifact = await (await this.ml()).validateModelArtifact({
      contractVersion: 1,
      modelVersionId: model.id,
      breadCategoryId: model.breadCategoryId,
      lifecycleStatus: model.lifecycleStatus,
      artifactKey: model.artifactKey,
      artifactSha256: model.artifactSha256,
    });
    if (!artifact.valid || artifact.trainingEnd !== model.trainingEnd ||
        artifact.featureVersion !== 1) {
      throw new AppError(409, "MODEL_ARTIFACT_INVALID",
        "The selected model artifact is missing or invalid.");
    }
  }

  async listTrainingCategories() {
    return (await this.repo()).listTrainingCategories();
  }

  async listModels(input: unknown) {
    if (typeof input !== "object" || input === null || Array.isArray(input)) {
      throw new AppError(400, "VALIDATION_ERROR", "Invalid model-list filters.");
    }
    const query = input as Record<string, unknown>;
    if (Object.keys(query).some((key) =>
      !["breadCategoryId", "page", "pageSize"].includes(key))) {
      throw new AppError(400, "VALIDATION_ERROR", "Unknown model-list filter.");
    }
    const categoryId = query.breadCategoryId;
    if (categoryId !== undefined &&
        (typeof categoryId !== "string" || !uuidPattern.test(categoryId))) {
      throw new AppError(400, "VALIDATION_ERROR",
        "A valid breadCategoryId is required.");
    }
    const parsePositive = (value: unknown, fallback: number): number => {
      if (value === undefined) return fallback;
      if (typeof value !== "string" || !/^[1-9]\d*$/.test(value)) {
        throw new AppError(400, "VALIDATION_ERROR", "Invalid model-list page.");
      }
      const parsed = Number(value);
      if (!Number.isSafeInteger(parsed)) {
        throw new AppError(400, "VALIDATION_ERROR", "Invalid model-list page.");
      }
      return parsed;
    };
    const page = parsePositive(query.page, 1);
    const pageSize = parsePositive(query.pageSize, 20);
    if (pageSize > 50 || (page - 1) * pageSize > 2_147_483_647) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Model-list pageSize must be at most 50 and page must be in range.");
    }
    const repo = await this.repo();
    await repo.assertStorageReady();
    const { items, total } = await repo.listModelReviews(
      typeof categoryId === "string" ? categoryId : null,
      (page - 1) * pageSize, pageSize,
    );
    return { items, page, pageSize, total };
  }

  async getModelDetails(modelVersionId: string) {
    if (!uuidPattern.test(modelVersionId)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid model version ID is required.");
    }
    const repo = await this.repo();
    await repo.assertStorageReady();
    const model = await repo.findModelReviewById(modelVersionId);
    if (!model) {
      throw new AppError(404, "MODEL_NOT_FOUND", "The model version was not found.");
    }
    return model;
  }

  async trainCandidates(actorUserId: string, input: unknown) {
    if (typeof input !== "object" || input === null || Array.isArray(input) ||
        Object.keys(input).length !== 1 || !("breadCategoryId" in input) ||
        typeof input.breadCategoryId !== "string" ||
        !uuidPattern.test(input.breadCategoryId)) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Only a valid breadCategoryId is accepted.");
    }
    const categoryId = input.breadCategoryId;
    const repo = await this.repo();
    await repo.assertStorageReady();
    if (!await repo.isActiveCategory(categoryId)) {
      throw new AppError(404, "ACTIVE_CATEGORY_NOT_FOUND",
        "An active bread category is required.");
    }
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const history = await (await this.history()).loadSelected(categoryId, today);
    if (history.distinctDayCount < 30) {
      throw new AppError(409, "INSUFFICIENT_HISTORY",
        `At least 30 validated sales days are required; ${history.distinctDayCount} are available.`);
    }
    const holdoutCount = Math.ceil(history.distinctDayCount * 0.2);
    const holdoutStart = history.observations[
      history.distinctDayCount - holdoutCount
    ]?.salesDate;
    if (!holdoutStart) throw new Error("Unable to choose a later holdout.");
    const result = await (await this.ml()).trainCandidates({
      contractVersion: 1,
      breadCategoryId: categoryId,
      rfModelVersionId: randomUUID(),
      lrModelVersionId: randomUUID(),
      holdoutStart,
      observations: history.observations,
    });
    const candidates = await repo.createCandidates(actorUserId, categoryId, result);
    return {
      breadCategoryId: categoryId,
      selectedDayCount: history.distinctDayCount,
      holdoutStart,
      historicalContextDefaultCount: result.historicalContextDefaultCount,
      trainingOrigins: result.trainingOrigins,
      holdoutOrigins: result.holdoutOrigins,
      candidates,
    };
  }

  async evaluateCandidate(actorUserId: string, candidateId: string) {
    if (!uuidPattern.test(candidateId)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid model version ID is required.");
    }
    const repo = await this.repo();
    await repo.assertStorageReady();
    const candidate = await repo.findModelById(candidateId);
    if (!candidate) {
      throw new AppError(404, "MODEL_NOT_FOUND", "The candidate model was not found.");
    }
    if (candidate.modelType !== "RANDOM_FOREST" ||
        candidate.lifecycleStatus !== "CANDIDATE" ||
        !candidate.trainingGroupId || !candidate.holdoutStart ||
        !candidate.trainingFingerprint) {
      throw new AppError(409, "MODEL_NOT_EVALUABLE",
        "A retained Random Forest candidate with holdout metadata is required.");
    }
    const baseline = await repo.findBaseline(candidate.trainingGroupId);
    if (!baseline || baseline.lifecycleStatus !== "CANDIDATE" ||
        baseline.breadCategoryId !== candidate.breadCategoryId ||
        baseline.trainingFingerprint !== candidate.trainingFingerprint) {
      throw new AppError(409, "BASELINE_NOT_EVALUABLE",
        "The matching Linear Regression candidate is unavailable.");
    }
    const active = await repo.findActive(candidate.breadCategoryId);
    if (active && active.modelType !== "RANDOM_FOREST") {
      throw new AppError(409, "ACTIVE_MODEL_INVALID",
        "The current active model is not a Random Forest.");
    }
    const today = bakeryDate(this.now(), await repo.getBakeryTimezone());
    const history = await (await this.history()).loadSelected(
      candidate.breadCategoryId, today,
    );
    if (active && !active.holdoutStart) {
      throw new AppError(409, "ACTIVE_MODEL_NOT_COMPARABLE",
        "The current model lacks a retained holdout boundary.");
    }
    const commonEarliestDate = [
      candidate.holdoutStart,
      ...(active ? [active.holdoutStart!, active.trainingEnd] : []),
    ].sort().at(-1)!;
    const holdoutStart = history.observations.find((item) =>
      item.salesDate >= commonEarliestDate &&
      (!active || item.salesDate > active.trainingEnd),
    )?.salesDate;
    if (!holdoutStart) {
      throw new AppError(409, "COMPARABLE_HOLDOUT_UNAVAILABLE",
        "No later sales day is available for both models' evaluation.");
    }
    const request: EvaluationInputDto = {
      contractVersion: 1,
      breadCategoryId: candidate.breadCategoryId,
      holdoutStart,
      observations: history.observations,
      models: [
        { role: "CANDIDATE_RF", modelVersionId: candidate.id,
          modelType: "RANDOM_FOREST", artifactKey: candidate.artifactKey },
        { role: "BASELINE_LR", modelVersionId: baseline.id,
          modelType: "LINEAR_REGRESSION", artifactKey: baseline.artifactKey },
      ],
    };
    if (active) request.models.push({
      role: "CURRENT_ACTIVE_RF", modelVersionId: active.id,
      modelType: "RANDOM_FOREST", artifactKey: active.artifactKey,
    });
    const result = await (await this.ml()).evaluateModels(request);
    const persisted = await repo.recordEvaluations(
      actorUserId, candidate, baseline, active?.id ?? null, result,
    );
    return {
      breadCategoryId: candidate.breadCategoryId,
      candidateModelVersionId: candidate.id,
      holdoutStart: result.holdoutStart,
      holdoutEnd: result.holdoutEnd,
      holdoutFingerprint: result.holdoutFingerprint,
      evaluationLabel: result.evaluationLabel,
      dataOrigins: result.dataOrigins,
      results: result.results.map((item) => ({
        ...item,
        evaluationId: persisted.find((row) => row.modelVersionId === item.modelVersionId)?.id,
      })),
    };
  }

  async activateCandidate(
    actorUserId: string,
    candidateId: string,
    input: unknown,
  ) {
    if (!uuidPattern.test(candidateId)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid model version ID is required.");
    }
    if (typeof input !== "object" || input === null || Array.isArray(input) ||
        Object.keys(input).length !== 2 ||
        !("confirm" in input) || input.confirm !== true ||
        !("evaluationId" in input) ||
        typeof input.evaluationId !== "string" ||
        !uuidPattern.test(input.evaluationId)) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Explicit confirmation and a candidate evaluation ID are required.");
    }
    const repo = await this.repo();
    await repo.assertStorageReady();
    const candidate = await repo.findModelById(candidateId);
    if (!candidate) {
      throw new AppError(404, "MODEL_NOT_FOUND", "The candidate model was not found.");
    }
    if (candidate.lifecycleStatus !== "CANDIDATE" ||
        candidate.modelType !== "RANDOM_FOREST" ||
        !candidate.artifactSha256 || !candidate.holdoutStart) {
      throw new AppError(409, "MODEL_NOT_ACTIVATABLE",
        "A retained Random Forest candidate is required.");
    }
    const candidateEvaluation = await repo.findEvaluationById(input.evaluationId);
    if (!candidateEvaluation || candidateEvaluation.modelVersionId !== candidateId ||
        !Number.isFinite(candidateEvaluation.mae)) {
      throw new AppError(409, "CANDIDATE_EVALUATION_MISSING",
        "A valid evaluation of this candidate is required.");
    }
    const active = await repo.findActive(candidate.breadCategoryId);
    const activeEvaluation = active
      ? await repo.findComparableEvaluation(active.id, candidateEvaluation.holdoutFingerprint)
      : null;
    if (active && (!activeEvaluation || !Number.isFinite(activeEvaluation.mae))) {
      throw new AppError(409, "ACTIVE_EVALUATION_MISSING",
        "Evaluate the current model on the same holdout first.");
    }
    if (activeEvaluation && candidateEvaluation.mae > activeEvaluation.mae) {
      throw new AppError(409, "MODEL_MAE_WORSE",
        "Candidate MAE exceeds the current model MAE on the same holdout.");
    }
    await this.assertValidArtifact(candidate);
    return repo.activateCandidate(
      actorUserId,
      candidate.id,
      candidateEvaluation.id,
      active?.id ?? null,
      activeEvaluation?.id ?? null,
      candidate.artifactSha256,
    );
  }

  async restorePreviousModel(
    actorUserId: string,
    previousModelId: string,
    input: unknown,
  ) {
    if (!uuidPattern.test(previousModelId)) {
      throw new AppError(400, "VALIDATION_ERROR", "A valid model version ID is required.");
    }
    if (typeof input !== "object" || input === null || Array.isArray(input) ||
        Object.keys(input).length !== 1 ||
        !("confirm" in input) || input.confirm !== true) {
      throw new AppError(400, "VALIDATION_ERROR",
        "Explicit restoration confirmation is required.");
    }
    const repo = await this.repo();
    await repo.assertStorageReady();
    const previous = await repo.findModelById(previousModelId);
    if (!previous) {
      throw new AppError(404, "MODEL_NOT_FOUND", "The previous model was not found.");
    }
    if (previous.lifecycleStatus !== "INACTIVE" ||
        previous.modelType !== "RANDOM_FOREST" ||
        !previous.artifactSha256 || !previous.holdoutStart) {
      throw new AppError(409, "MODEL_NOT_RESTORABLE",
        "A retained, previously active Random Forest model is required.");
    }
    const active = await repo.findActive(previous.breadCategoryId);
    if (!active || active.id === previous.id ||
        active.modelType !== "RANDOM_FOREST") {
      throw new AppError(409, "ACTIVE_MODEL_NOT_FOUND",
        "A different current Random Forest model is required for restoration.");
    }
    if (!await repo.hasValidEvaluation(previous.id, previous.trainingEnd)) {
      throw new AppError(409, "MODEL_EVALUATION_MISSING",
        "The previous model has no valid retained evaluation.");
    }
    await this.assertValidArtifact(previous);
    return repo.restorePreviousModel(
      actorUserId, previous.id, active.id, previous.artifactSha256,
    );
  }
}
