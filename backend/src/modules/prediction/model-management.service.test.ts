import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import type { TrainingCandidateInputDto } from "./fast-api-ml.client.js";
import type { EvaluationInputDto, EvaluationResponseDto } from "./model-evaluation.dto.js";
import { ModelManagementService } from "./model-management.service.js";
import type {
  ModelManagementRepo, ModelVersionReview, StoredModelVersion,
} from "./model-management.repo.js";
import type { PredictionHistoryService } from "./prediction-history.service.js";
import type { FastApiMlClient } from "./fast-api-ml.client.js";

const category = "00000000-0000-4000-8000-000000000001";
const actor = "00000000-0000-4000-8000-000000000002";
const candidateId = "00000000-0000-4000-8000-000000000003";
const baselineId = "00000000-0000-4000-8000-000000000004";
const activeId = "00000000-0000-4000-8000-000000000005";
const groupId = "00000000-0000-4000-8000-000000000006";

const review: ModelVersionReview = {
  id: candidateId, version: 2, breadCategoryId: category,
  breadCategoryName: "Wholemeal Bread", modelType: "RANDOM_FOREST",
  lifecycleStatus: "CANDIDATE", createdAt: "2026-11-04T00:00:00Z",
  activatedAt: null, trainingStart: "2026-10-05",
  trainingEnd: "2026-10-28", holdoutStart: "2026-10-29",
  trainingGroupId: groupId,
  featureVersion: 1,
  trainingOriginCounts: { ACTUAL_TRANSACTION: 0,
    IMPORTED_HISTORICAL: 0, SIMULATION_GENERATED: 24 },
  holdoutOriginCounts: { ACTUAL_TRANSACTION: 0,
    IMPORTED_HISTORICAL: 0, SIMULATION_GENERATED: 6 },
  historicalContextDefaultCount: 0,
  latestEvaluation: {
    id: "00000000-0000-4000-8000-000000000007",
    evaluatedAt: "2026-11-04T01:00:00Z",
    holdoutStart: "2026-10-29", holdoutEnd: "2026-11-03",
    holdoutFingerprint: "f".repeat(64), evaluationLabel: "SIMULATION_BASED",
    dataOrigins: ["SIMULATION_GENERATED"], mae: 2, rmse: 3,
    mape: null, rSquared: null, sampleCount: 6, mapeSampleCount: 0,
  },
};

const observations = Array.from({ length: 30 }, (_, index) => ({
  id: `00000000-0000-4000-8000-${(index + 100).toString(16).padStart(12, "0")}`,
  breadCategoryId: category,
  salesDate: new Date(Date.UTC(2026, 9, 5 + index)).toISOString().slice(0, 10),
  unitsSold: index,
  dataOrigin: "SIMULATION_GENERATED" as const,
  sourceDailyResultId: `00000000-0000-4000-8000-${(index + 500).toString(16).padStart(12, "0")}`,
  externalSourceReference: null,
}));

function model(id: string, type: StoredModelVersion["modelType"],
  status: StoredModelVersion["lifecycleStatus"],
  end = "2026-10-28", holdout = "2026-10-29"): StoredModelVersion {
  return {
    id, version: 1, breadCategoryId: category, modelType: type,
    artifactKey: `models/${id}.joblib`, artifactSha256: "b".repeat(64),
    trainingStart: "2026-10-05",
    trainingEnd: end, holdoutStart: holdout,
    trainingFingerprint: "a".repeat(64), trainingGroupId: groupId,
    lifecycleStatus: status,
  };
}

function history(days = 30): Pick<PredictionHistoryService, "loadSelected"> {
  return { async loadSelected() {
    return { observations: observations.slice(0, days),
      distinctDayCount: days, rejected: [] };
  } };
}

function baseRepo(): Pick<ModelManagementRepo,
  "assertStorageReady" | "listTrainingCategories" | "listModelReviews" | "findModelReviewById" |
  "getBakeryTimezone" | "isActiveCategory" | "findModelById" |
  "findBaseline" | "findActive" | "findEvaluationById" |
  "findComparableEvaluation" | "hasValidEvaluation" |
  "createCandidates" | "recordEvaluations" |
  "activateCandidate" | "restorePreviousModel"> {
  return {
    async assertStorageReady() {},
    async listTrainingCategories() {
      return [{ id: category, name: "Wholemeal Bread", displayOrder: 1 }];
    },
    async listModelReviews() { return { items: [review], total: 1 }; },
    async findModelReviewById() { return review; },
    async getBakeryTimezone() { return "Asia/Kuala_Lumpur"; },
    async isActiveCategory() { return true; },
    async findModelById() { return model(candidateId, "RANDOM_FOREST", "CANDIDATE"); },
    async findBaseline() { return model(baselineId, "LINEAR_REGRESSION", "CANDIDATE"); },
    async findActive() { return null; },
    async findEvaluationById(id) {
      return { id, modelVersionId: candidateId, mae: 2,
        holdoutFingerprint: "f".repeat(64) };
    },
    async findComparableEvaluation() {
      return { id: "00000000-0000-4000-8000-000000000008",
        modelVersionId: activeId, mae: 3,
        holdoutFingerprint: "f".repeat(64) };
    },
    async hasValidEvaluation() { return true; },
    async createCandidates(_actor, _category, result) {
      return result.candidates.map((item, index) => ({
        id: item.modelVersionId, version: index + 1,
        modelType: item.modelType, lifecycleStatus: "CANDIDATE" as const,
        trainingGroupId: groupId,
      }));
    },
    async recordEvaluations(_actor, _candidate, _baseline, _active, result) {
      return result.results.map((item, index) => ({
        id: `eval-${index}`, modelVersionId: item.modelVersionId,
        mae: item.mae, holdoutFingerprint: result.holdoutFingerprint,
      }));
    },
    async activateCandidate(actorId, candidate, evaluation, active, activeEvaluation, sha) {
      return { modelVersionId: candidate, lifecycleStatus: "ACTIVE" as const,
        previousActiveModelVersionId: active, candidateMae: 2,
        previousMae: active ? 3 : null,
        holdoutFingerprint: "f".repeat(64),
        activatedAt: "2026-11-04T00:00:00Z" };
    },
    async restorePreviousModel(_actor, previous, active) {
      return { modelVersionId: previous, lifecycleStatus: "ACTIVE" as const,
        previousActiveModelVersionId: active,
        restoredAt: "2026-11-04T00:00:00Z" };
    },
  };
}

function ml(
  train: (input: TrainingCandidateInputDto) => Promise<ReturnType<FastApiMlClient["trainCandidates"]> extends Promise<infer T> ? T : never>,
  evaluate: (input: EvaluationInputDto) => Promise<EvaluationResponseDto>,
): Pick<FastApiMlClient, "trainCandidates" | "evaluateModels" | "validateModelArtifact"> {
  return { trainCandidates: train, evaluateModels: evaluate,
    async validateModelArtifact(input) {
      return { modelVersionId: input.modelVersionId,
        breadCategoryId: input.breadCategoryId, valid: true,
        trainingEnd: "2026-10-28", featureVersion: 1 };
    } };
}

test("T-DP-ADMIN-01 [BR-DP-03, FR-DP-06]: administrator training selects 30 days and later 20% holdout", async () => {
  let persistedActor = "";
  const repo = baseRepo();
  repo.createCandidates = async (actorId, categoryId, result) => {
    persistedActor = actorId;
    assert.equal(categoryId, category);
    assert.equal(result.holdoutStart, "2026-10-29");
    return result.candidates.map((item, index) => ({
      id: item.modelVersionId, version: index + 1,
      modelType: item.modelType, lifecycleStatus: "CANDIDATE" as const,
      trainingGroupId: groupId,
    }));
  };
  const service = new ModelManagementService(repo, history(), ml(
    async (input) => {
      assert.equal(input.observations.length, 30);
      assert.equal(input.holdoutStart, "2026-10-29");
      return {
        breadCategoryId: category, trainingStart: "2026-10-05",
        trainingEnd: "2026-10-28", holdoutStart: input.holdoutStart,
        fitSampleCount: 23, holdoutSampleCount: 6,
        historicalContextDefaultCount: 29, featureVersion: 1,
        trainingFingerprint: "a".repeat(64),
        trainingOrigins: { ACTUAL_TRANSACTION: 0, IMPORTED_HISTORICAL: 0,
          SIMULATION_GENERATED: 24 },
        holdoutOrigins: { ACTUAL_TRANSACTION: 0, IMPORTED_HISTORICAL: 0,
          SIMULATION_GENERATED: 6 },
        candidates: [
          { modelVersionId: input.rfModelVersionId, modelType: "RANDOM_FOREST",
            artifactKey: "models/rf.joblib", sha256: "b".repeat(64) },
          { modelVersionId: input.lrModelVersionId, modelType: "LINEAR_REGRESSION",
            artifactKey: "models/lr.joblib", sha256: "c".repeat(64) },
        ],
      };
    },
    async () => { throw new Error("Evaluation should not run during training."); },
  ), () => new Date("2026-11-04T02:00:00.000Z"));
  const result = await service.trainCandidates(actor, { breadCategoryId: category });
  assert.equal(persistedActor, actor);
  assert.equal(result.candidates.length, 2);
  assert(result.candidates.every((item) => item.lifecycleStatus === "CANDIDATE"));
});

test("T-DP-ADMIN-02 [BR-DP-03]: fewer than 30 days blocks training before ML", async () => {
  const service = new ModelManagementService(baseRepo(), history(29), ml(
    async () => { throw new Error("ML must not be called."); },
    async () => { throw new Error("ML must not be called."); },
  ), () => new Date("2026-11-04T02:00:00.000Z"));
  await assert.rejects(service.trainCandidates(actor, { breadCategoryId: category }),
    (error: unknown) => error instanceof AppError &&
      error.code === "INSUFFICIENT_HISTORY");
  await assert.rejects(service.trainCandidates(actor, {
    breadCategoryId: category, role: "SYSTEM_ADMINISTRATOR",
  }), (error: unknown) => error instanceof AppError &&
    error.code === "VALIDATION_ERROR");
});

test("T-DP-ADMIN-06 [NFR-REL-01]: absent schema blocks training before artifacts are created", async () => {
  const repo = baseRepo();
  repo.assertStorageReady = async () => {
    throw new AppError(503, "MODEL_SCHEMA_NOT_READY", "Migration missing.");
  };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("ML must not create artifacts."); },
    async () => { throw new Error("ML must not run."); },
  ));
  await assert.rejects(service.trainCandidates(actor, { breadCategoryId: category }),
    (error: unknown) => error instanceof AppError &&
      error.code === "MODEL_SCHEMA_NOT_READY");
});

test("T-DP-ADMIN-03 [FR-DP-06, NFR-ACC-05]: evaluation selects a common later holdout and persists all results", async () => {
  const repo = baseRepo();
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE",
    "2026-10-31", "2026-11-01");
  let persisted = false;
  repo.recordEvaluations = async (actorId, candidate, baseline, active, result) => {
    assert.equal(actorId, actor);
    assert.equal(candidate.id, candidateId);
    assert.equal(baseline.id, baselineId);
    assert.equal(active, activeId);
    assert.equal(result.holdoutStart, "2026-11-01");
    persisted = true;
    return result.results.map((item, index) => ({ id: `eval-${index}`,
      modelVersionId: item.modelVersionId, mae: item.mae,
      holdoutFingerprint: result.holdoutFingerprint }));
  };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("Training should not run during evaluation."); },
    async (input) => {
      assert.equal(input.holdoutStart, "2026-11-01");
      assert.deepEqual(input.models.map((item) => item.role), [
        "CANDIDATE_RF", "BASELINE_LR", "CURRENT_ACTIVE_RF",
      ]);
      return {
        breadCategoryId: category, holdoutStart: input.holdoutStart,
        holdoutEnd: "2026-11-03", holdoutManifest: {},
        holdoutFingerprint: "f".repeat(64),
        dataOrigins: ["SIMULATION_GENERATED"],
        evaluationLabel: "SIMULATION_BASED",
        originCounts: { ACTUAL_TRANSACTION: 0, IMPORTED_HISTORICAL: 0,
          SIMULATION_GENERATED: 3 },
        results: input.models.map((item) => ({
          role: item.role, modelVersionId: item.modelVersionId,
          modelType: item.modelType, mae: 2, rmse: 2,
          mape: null, rSquared: null, sampleCount: 3,
          mapeSampleCount: 0, mapeUnavailableReason: "NO_NONZERO_ACTUALS",
          rSquaredUnavailableReason: "CONSTANT_ACTUALS",
          predictions: [],
        })),
      };
    },
  ), () => new Date("2026-11-04T02:00:00.000Z"));
  const result = await service.evaluateCandidate(actor, candidateId);
  assert(persisted);
  assert.equal(result.results.length, 3);
  assert(result.results.every((item) => item.evaluationId !== undefined));
});

test("T-DP-ADMIN-04 [NFR-ACC-05]: no untouched common holdout blocks comparison", async () => {
  const repo = baseRepo();
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE",
    "2026-11-03", "2026-11-04");
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("ML must not run."); },
    async () => { throw new Error("ML must not run."); },
  ), () => new Date("2026-11-04T02:00:00.000Z"));
  await assert.rejects(service.evaluateCandidate(actor, candidateId),
    (error: unknown) => error instanceof AppError &&
      error.code === "COMPARABLE_HOLDOUT_UNAVAILABLE");
});

test("T-DP-ADMIN-07 [FR-DP-06]: first activation needs explicit confirmation, evaluation and valid artifact", async () => {
  const repo = baseRepo();
  let activated = false;
  repo.activateCandidate = async (_actor, candidate, evaluation, active, activeEvaluation) => {
    assert.equal(candidate, candidateId);
    assert.equal(evaluation, "00000000-0000-4000-8000-000000000007");
    assert.equal(active, null);
    assert.equal(activeEvaluation, null);
    activated = true;
    return { modelVersionId: candidateId, lifecycleStatus: "ACTIVE",
      previousActiveModelVersionId: null, candidateMae: 2,
      previousMae: null, holdoutFingerprint: "f".repeat(64),
      activatedAt: "2026-11-04T00:00:00Z" };
  };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  ));
  for (const body of [{}, { confirm: false, evaluationId: "00000000-0000-4000-8000-000000000007" },
    { confirm: true, evaluationId: "00000000-0000-4000-8000-000000000007", role: "SYSTEM_ADMINISTRATOR" }]) {
    await assert.rejects(service.activateCandidate(actor, candidateId, body),
      (error: unknown) => error instanceof AppError && error.code === "VALIDATION_ERROR");
  }
  assert.equal(activated, false);
  const result = await service.activateCandidate(actor, candidateId, {
    confirm: true, evaluationId: "00000000-0000-4000-8000-000000000007",
  });
  assert.equal(result.lifecycleStatus, "ACTIVE");
  assert.equal(result.previousActiveModelVersionId, null);
  assert(activated);
});

test("T-DP-ADMIN-08 [NFR-ACC-05]: higher candidate MAE retains current model", async () => {
  const repo = baseRepo();
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE");
  repo.findEvaluationById = async (id) => ({
    id, modelVersionId: candidateId, mae: 4, holdoutFingerprint: "f".repeat(64),
  });
  repo.findComparableEvaluation = async () => ({
    id: "00000000-0000-4000-8000-000000000008",
    modelVersionId: activeId, mae: 3, holdoutFingerprint: "f".repeat(64),
  });
  repo.activateCandidate = async () => { throw new Error("No mutation is allowed."); };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("ML must not run."); },
    async () => { throw new Error("ML must not run."); },
  ));
  await assert.rejects(service.activateCandidate(actor, candidateId, {
    confirm: true, evaluationId: "00000000-0000-4000-8000-000000000007",
  }), (error: unknown) => error instanceof AppError &&
    error.code === "MODEL_MAE_WORSE");
});

test("T-DP-ADMIN-10 [NFR-ACC-05]: equal MAE permits confirmed replacement", async () => {
  const repo = baseRepo();
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE");
  repo.findEvaluationById = async (id) => ({
    id, modelVersionId: candidateId, mae: 3, holdoutFingerprint: "f".repeat(64),
  });
  let called = false;
  repo.activateCandidate = async (_actor, _candidate, _candidateEvaluation,
    expectedActive, activeEvaluation) => {
    called = true;
    assert.equal(expectedActive, activeId);
    assert.equal(activeEvaluation, "00000000-0000-4000-8000-000000000008");
    return { modelVersionId: candidateId, lifecycleStatus: "ACTIVE",
      previousActiveModelVersionId: activeId, candidateMae: 3,
      previousMae: 3, holdoutFingerprint: "f".repeat(64),
      activatedAt: "2026-11-04T00:00:00Z" };
  };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  ));
  const result = await service.activateCandidate(actor, candidateId, {
    confirm: true, evaluationId: "00000000-0000-4000-8000-000000000007",
  });
  assert.equal(result.previousMae, 3);
  assert(called);
});

test("T-DP-ADMIN-09 [FR-DP-06]: invalid candidate artifact blocks activation", async () => {
  const repo = baseRepo();
  repo.activateCandidate = async () => { throw new Error("No mutation is allowed."); };
  const mlAdapter = ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  );
  mlAdapter.validateModelArtifact = async (input) => ({
    modelVersionId: input.modelVersionId,
    breadCategoryId: input.breadCategoryId,
    valid: false, trainingEnd: null, featureVersion: null,
  });
  const service = new ModelManagementService(repo, history(), mlAdapter);
  await assert.rejects(service.activateCandidate(actor, candidateId, {
    confirm: true, evaluationId: "00000000-0000-4000-8000-000000000007",
  }), (error: unknown) => error instanceof AppError &&
    error.code === "MODEL_ARTIFACT_INVALID");
});

test("T-DP-ADMIN-11 [FR-DP-12, NFR-REL-02]: confirmed restoration selects a retained valid version", async () => {
  const repo = baseRepo();
  repo.findModelById = async () => model(candidateId, "RANDOM_FOREST", "INACTIVE");
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE");
  repo.findComparableEvaluation = async () => {
    throw new Error("Candidate MAE comparison does not govern restoration.");
  };
  let restored = false;
  repo.restorePreviousModel = async (actorId, previousId, currentId, sha) => {
    assert.equal(actorId, actor);
    assert.equal(previousId, candidateId);
    assert.equal(currentId, activeId);
    assert.equal(sha, "b".repeat(64));
    restored = true;
    return { modelVersionId: previousId, lifecycleStatus: "ACTIVE",
      previousActiveModelVersionId: currentId,
      restoredAt: "2026-11-04T00:00:00Z" };
  };
  const mlAdapter = ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  );
  mlAdapter.validateModelArtifact = async (input) => {
    assert.equal(input.lifecycleStatus, "INACTIVE");
    return { modelVersionId: input.modelVersionId,
      breadCategoryId: input.breadCategoryId, valid: true,
      trainingEnd: "2026-10-28", featureVersion: 1 };
  };
  const service = new ModelManagementService(repo, history(), mlAdapter);
  for (const body of [{}, { confirm: false },
    { confirm: true, activeModelVersionId: activeId }]) {
    await assert.rejects(service.restorePreviousModel(actor, candidateId, body),
      (error: unknown) => error instanceof AppError &&
        error.code === "VALIDATION_ERROR");
  }
  assert.equal(restored, false);
  const result = await service.restorePreviousModel(actor, candidateId, {
    confirm: true,
  });
  assert.equal(result.previousActiveModelVersionId, activeId);
  assert(restored);
});

test("T-DP-ADMIN-12 [FR-DP-12]: only an inactive prior RF with evaluation is restorable", async () => {
  const repo = baseRepo();
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE");
  repo.restorePreviousModel = async () => {
    throw new Error("Invalid prior versions must not mutate storage.");
  };
  const service = new ModelManagementService(repo, history(), ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  ));
  for (const invalid of [
    model(candidateId, "RANDOM_FOREST", "CANDIDATE"),
    model(candidateId, "LINEAR_REGRESSION", "INACTIVE"),
  ]) {
    repo.findModelById = async () => invalid;
    await assert.rejects(service.restorePreviousModel(actor, candidateId,
      { confirm: true }), (error: unknown) => error instanceof AppError &&
        error.code === "MODEL_NOT_RESTORABLE");
  }
  repo.findModelById = async () => model(candidateId, "RANDOM_FOREST", "INACTIVE");
  repo.hasValidEvaluation = async () => false;
  await assert.rejects(service.restorePreviousModel(actor, candidateId,
    { confirm: true }), (error: unknown) => error instanceof AppError &&
      error.code === "MODEL_EVALUATION_MISSING");
});

test("T-DP-ADMIN-13 [FR-DP-12, NFR-REL-02]: invalid retained artifact blocks restoration", async () => {
  const repo = baseRepo();
  repo.findModelById = async () => model(candidateId, "RANDOM_FOREST", "INACTIVE");
  repo.findActive = async () => model(activeId, "RANDOM_FOREST", "ACTIVE");
  repo.restorePreviousModel = async () => {
    throw new Error("No mutation is allowed after artifact failure.");
  };
  const mlAdapter = ml(
    async () => { throw new Error("Training must not run."); },
    async () => { throw new Error("Evaluation must not run."); },
  );
  mlAdapter.validateModelArtifact = async (input) => ({
    modelVersionId: input.modelVersionId,
    breadCategoryId: input.breadCategoryId,
    valid: false, trainingEnd: null, featureVersion: null,
  });
  const service = new ModelManagementService(repo, history(), mlAdapter);
  await assert.rejects(service.restorePreviousModel(actor, candidateId,
    { confirm: true }), (error: unknown) => error instanceof AppError &&
      error.code === "MODEL_ARTIFACT_INVALID");
});

test("T-DP-ADMIN-14 [FR-DP-12]: model history is category-filtered and capped at 50 per page", async () => {
  const repo = baseRepo();
  let argumentsSeen: [string | null, number, number] | null = null;
  repo.listModelReviews = async (categoryId, offset, pageSize) => {
    argumentsSeen = [categoryId, offset, pageSize];
    return { items: [review], total: 101 };
  };
  const service = new ModelManagementService(repo);
  const page = await service.listModels({ breadCategoryId: category,
    page: "2", pageSize: "50" });
  assert.deepEqual(argumentsSeen, [category, 50, 50]);
  assert.equal(page.total, 101);
  assert.equal(page.items[0]?.latestEvaluation?.evaluationLabel,
    "SIMULATION_BASED");
  for (const invalid of [
    { pageSize: "51" }, { page: "0" }, { breadCategoryId: "bad" },
    { role: "SYSTEM_ADMINISTRATOR" }, { page: ["1", "2"] },
  ]) {
    await assert.rejects(service.listModels(invalid),
      (error: unknown) => error instanceof AppError &&
        error.code === "VALIDATION_ERROR");
  }
});

test("T-DP-ADMIN-15 [FR-DP-11, FR-DP-12]: detail exposes review metrics without artifact location", async () => {
  const repo = baseRepo();
  const service = new ModelManagementService(repo);
  const result = await service.getModelDetails(candidateId);
  assert.equal(result.latestEvaluation?.id,
    "00000000-0000-4000-8000-000000000007");
  assert.equal(result.latestEvaluation?.mape, null);
  assert.equal("artifactKey" in result, false);
  assert.equal("artifactSha256" in result, false);
  repo.findModelReviewById = async () => null;
  await assert.rejects(service.getModelDetails(candidateId),
    (error: unknown) => error instanceof AppError && error.code === "MODEL_NOT_FOUND");
});
