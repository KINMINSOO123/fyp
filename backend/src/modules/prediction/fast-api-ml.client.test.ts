import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { FastApiMlClient } from "./fast-api-ml.client.js";
import type {
  TrainingCandidateInputDto,
} from "./fast-api-ml.client.js";
import type { PredictionCategoryInputDto } from "./prediction-category.dto.js";

const request: PredictionCategoryInputDto = {
  contractVersion: 1,
  breadCategoryId: "00000000-0000-4000-8000-000000000001",
  targetDate: "2026-11-04",
  observations: [],
  configuredBaseQuantity: 20,
  factors: {
    weekdayFactor: 1,
    monsoonFactor: 1,
    weatherFactor: 1,
    holidayFactor: 1,
  },
  confidenceThreshold: 75,
  activeModel: null,
};

const responseBody = {
  breadCategoryId: request.breadCategoryId,
  targetDate: request.targetDate,
  predictionMode: "COLD_START",
  predictedUnitsSold: 20,
  modelVersionId: null,
  confidence: null,
  lowConfidence: true,
  confidenceLabel: "Low Confidence - Cold-Start Heuristic",
  reason: "INSUFFICIENT_HISTORY",
  baseDemand: 20,
  baseSource: "CONFIGURED_BASE",
};

function client(fetcher: typeof fetch): FastApiMlClient {
  return new FastApiMlClient({
    baseUrl: "http://127.0.0.1:8000",
    internalToken: "test-only-secret",
    fetcher,
  });
}

test("T-DP-ML-01 [FR-DP-07, NFR-SEC-01]: sends internal DTO and accepts nullable cold-start confidence", async () => {
  const ml = client(async (input, init) => {
    assert.equal(String(input), "http://127.0.0.1:8000/predict");
    assert.equal(init?.method, "POST");
    assert.equal((init?.headers as Record<string, string>)["X-ML-Internal-Token"],
      "test-only-secret");
    assert.deepEqual(JSON.parse(init?.body as string), request);
    return Response.json(responseBody);
  });
  const result = await ml.predictCategory(request);
  assert.equal(result.predictionMode, "COLD_START");
  assert.equal(result.confidence, null);
  assert.equal(result.modelVersionId, null);
});

test("T-DP-ML-02 [FR-DP-07, NFR-ACC-08]: rejects wrong category or invented confidence", async () => {
  for (const bad of [
    { ...responseBody, breadCategoryId: "another-category" },
    { ...responseBody, confidence: 65 },
    { ...responseBody, modelVersionId: "model-1" },
  ]) {
    await assert.rejects(
      client(async () => Response.json(bad)).predictCategory(request),
      (error: unknown) => error instanceof AppError &&
        error.statusCode === 502 && error.code === "ML_CONTRACT_ERROR",
    );
  }
});

test("T-DP-ML-03 [FR-DP-06]: distinguishes unfinished model inference", async () => {
  const ml = client(async () => Response.json(
    { detail: { code: "MODEL_INFERENCE_NOT_READY" } }, { status: 503 },
  ));
  await assert.rejects(ml.predictCategory(request),
    (error: unknown) => error instanceof AppError &&
      error.code === "MODEL_INFERENCE_NOT_READY");
});

test("T-DP-ML-04 [NFR-SEC-01, NFR-DAT-01]: handles timeout and internal contract rejection", async () => {
  await assert.rejects(
    client(async () => { throw new Error("network down"); }).predictCategory(request),
    (error: unknown) => error instanceof AppError && error.code === "ML_UNAVAILABLE",
  );
  await assert.rejects(
    client(async () => Response.json({ detail: [] }, { status: 422 }))
      .predictCategory(request),
    (error: unknown) => error instanceof AppError && error.code === "ML_CONTRACT_ERROR",
  );
  assert.throws(() => new FastApiMlClient({
    baseUrl: "http://bakery.example:8000", internalToken: "secret",
  }), /HTTPS/);
  assert.throws(() => new FastApiMlClient({
    baseUrl: "http://127.0.0.1:8000", internalToken: " ",
  }), /required/);
});

test("T-DP-ML-05 [FR-DP-06, NFR-ACC-08]: accepts matching active-model result", async () => {
  const modelRequest: PredictionCategoryInputDto = {
    ...request,
    activeModel: {
      breadCategoryId: request.breadCategoryId,
      modelVersionId: "00000000-0000-4000-8000-000000000002",
      modelType: "RANDOM_FOREST",
      lifecycleStatus: "ACTIVE",
      artifactKey: "models/candidate.joblib",
    },
  };
  const result = await client(async () => Response.json({
    breadCategoryId: request.breadCategoryId,
    targetDate: request.targetDate,
    predictionMode: "MODEL",
    predictedUnitsSold: 18,
    modelVersionId: modelRequest.activeModel?.modelVersionId,
    confidence: 74.9,
    lowConfidence: true,
    confidenceLabel: "Low Confidence",
    reason: "MODEL_READY",
  })).predictCategory(modelRequest);
  assert.equal(result.predictionMode, "MODEL");
  assert.equal(result.confidence, 74.9);
});

test("T-DP-ML-06 [NFR-ACC-08]: rejects model confidence or version mismatch", async () => {
  const modelRequest: PredictionCategoryInputDto = {
    ...request,
    activeModel: {
      breadCategoryId: request.breadCategoryId,
      modelVersionId: "00000000-0000-4000-8000-000000000002",
      modelType: "RANDOM_FOREST",
      lifecycleStatus: "ACTIVE",
      artifactKey: "models/candidate.joblib",
    },
  };
  const base = {
    breadCategoryId: request.breadCategoryId,
    targetDate: request.targetDate,
    predictionMode: "MODEL",
    predictedUnitsSold: 18,
    modelVersionId: modelRequest.activeModel?.modelVersionId,
    confidence: 74.9,
    lowConfidence: true,
    confidenceLabel: "Low Confidence",
    reason: "MODEL_READY",
  };
  for (const bad of [
    { ...base, modelVersionId: "wrong" },
    { ...base, confidence: null },
    { ...base, lowConfidence: false },
  ]) {
    await assert.rejects(
      client(async () => Response.json(bad)).predictCategory(modelRequest),
      (error: unknown) => error instanceof AppError &&
        error.code === "ML_CONTRACT_ERROR",
    );
  }
});

test("T-DP-ML-07 [BR-DP-03, FR-DP-06]: accepts candidate metadata without activation", async () => {
  const training: TrainingCandidateInputDto = {
    contractVersion: 1,
    breadCategoryId: request.breadCategoryId,
    rfModelVersionId: "00000000-0000-4000-8000-000000000002",
    lrModelVersionId: "00000000-0000-4000-8000-000000000003",
    holdoutStart: "2026-10-29",
    observations: Array.from({ length: 30 }, (_, index) => ({
      id: `00000000-0000-4000-8000-${(index + 100).toString(16).padStart(12, "0")}`,
      breadCategoryId: request.breadCategoryId,
      salesDate: new Date(Date.UTC(2026, 9, 5 + index)).toISOString().slice(0, 10),
      unitsSold: index,
      dataOrigin: "SIMULATION_GENERATED" as const,
      sourceDailyResultId: `00000000-0000-4000-8000-${(index + 500).toString(16).padStart(12, "0")}`,
      externalSourceReference: null,
    })),
  };
  const trained = await client(async (input, init) => {
    assert.equal(String(input), "http://127.0.0.1:8000/train");
    assert.deepEqual(JSON.parse(init?.body as string), training);
    return Response.json({
      breadCategoryId: training.breadCategoryId,
      trainingStart: "2026-10-05",
      trainingEnd: "2026-10-28",
      holdoutStart: training.holdoutStart,
      fitSampleCount: 23,
      holdoutSampleCount: 6,
      historicalContextDefaultCount: 29,
      featureVersion: 1,
      trainingFingerprint: "c".repeat(64),
      trainingOrigins: {
        ACTUAL_TRANSACTION: 0, IMPORTED_HISTORICAL: 0, SIMULATION_GENERATED: 24,
      },
      holdoutOrigins: {
        ACTUAL_TRANSACTION: 0, IMPORTED_HISTORICAL: 0, SIMULATION_GENERATED: 6,
      },
      candidates: [
        { modelVersionId: training.rfModelVersionId,
          modelType: "RANDOM_FOREST", artifactKey: "models/rf.joblib",
          sha256: "a".repeat(64) },
        { modelVersionId: training.lrModelVersionId,
          modelType: "LINEAR_REGRESSION", artifactKey: "models/lr.joblib",
          sha256: "b".repeat(64) },
      ],
    });
  }).trainCandidates(training);
  assert.equal(trained.candidates[0]?.modelType, "RANDOM_FOREST");
  assert.equal("lifecycleStatus" in trained, false);
});

test("T-DP-ML-10 [FR-DP-06]: artifact check requires matching identity and retained file metadata", async () => {
  const input = {
    contractVersion: 1 as const,
    modelVersionId: "00000000-0000-4000-8000-000000000002",
    breadCategoryId: request.breadCategoryId,
    lifecycleStatus: "CANDIDATE" as const,
    artifactKey: "models/candidate.joblib",
    artifactSha256: "a".repeat(64),
  };
  const valid = await client(async (url, init) => {
    assert.equal(String(url), "http://127.0.0.1:8000/artifacts/validate");
    assert.deepEqual(JSON.parse(init?.body as string), input);
    return Response.json({
      modelVersionId: input.modelVersionId,
      breadCategoryId: input.breadCategoryId,
      valid: true, trainingEnd: "2026-10-28", featureVersion: 1,
    });
  }).validateModelArtifact(input);
  assert.equal(valid.valid, true);
  await assert.rejects(client(async () => Response.json({
    modelVersionId: "wrong", breadCategoryId: input.breadCategoryId,
    valid: true, trainingEnd: "2026-10-28", featureVersion: 1,
  })).validateModelArtifact(input),
  (error: unknown) => error instanceof AppError && error.code === "ML_CONTRACT_ERROR");
});
