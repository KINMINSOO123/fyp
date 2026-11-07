import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../../shared/AppError.js";
import { FastApiMlClient } from "./fast-api-ml.client.js";
import type { EvaluationInputDto } from "./model-evaluation.dto.js";

const category = "00000000-0000-4000-8000-000000000001";
const rfId = "00000000-0000-4000-8000-000000000002";
const lrId = "00000000-0000-4000-8000-000000000003";

const observations: EvaluationInputDto["observations"] = [
  { id: "row-1", breadCategoryId: category, salesDate: "2026-10-01",
    unitsSold: 5, dataOrigin: "ACTUAL_TRANSACTION", sourceDailyResultId: null,
    externalSourceReference: "receipt-1" },
  { id: "row-2", breadCategoryId: category, salesDate: "2026-10-02",
    unitsSold: 0, dataOrigin: "ACTUAL_TRANSACTION", sourceDailyResultId: null,
    externalSourceReference: "receipt-2" },
  { id: "row-3", breadCategoryId: category, salesDate: "2026-10-03",
    unitsSold: 10, dataOrigin: "SIMULATION_GENERATED", sourceDailyResultId: "result-3",
    externalSourceReference: null },
];

const request: EvaluationInputDto = {
  contractVersion: 1,
  breadCategoryId: category,
  holdoutStart: "2026-10-02",
  observations,
  models: [
    { role: "CANDIDATE_RF", modelVersionId: rfId,
      modelType: "RANDOM_FOREST", artifactKey: "models/rf.joblib" },
    { role: "BASELINE_LR", modelVersionId: lrId,
      modelType: "LINEAR_REGRESSION", artifactKey: "models/lr.joblib" },
  ],
};

const response = {
  breadCategoryId: category,
  holdoutStart: request.holdoutStart,
  holdoutEnd: "2026-10-03",
  holdoutManifest: {
    breadCategoryId: category,
    featureVersion: 1,
    holdoutStart: request.holdoutStart,
    priorObservationIds: ["row-1"],
    holdoutRows: observations.slice(1).map((row) => ({ ...row, contextFactors: null })),
    featureHistoryFingerprint: "a".repeat(64),
  },
  holdoutFingerprint: "b".repeat(64),
  dataOrigins: ["ACTUAL_TRANSACTION", "SIMULATION_GENERATED"],
  evaluationLabel: "SIMULATION_BASED",
  originCounts: {
    ACTUAL_TRANSACTION: 1, IMPORTED_HISTORICAL: 0, SIMULATION_GENERATED: 1,
  },
  results: [
    { role: "CANDIDATE_RF", modelVersionId: rfId, modelType: "RANDOM_FOREST",
      mae: 2, rmse: 2, mape: 20, rSquared: 0.84, sampleCount: 2,
      mapeSampleCount: 1, mapeUnavailableReason: null,
      rSquaredUnavailableReason: null,
      predictions: [
        { salesDate: "2026-10-02", predictedUnitsSold: 2 },
        { salesDate: "2026-10-03", predictedUnitsSold: 8 },
      ] },
    { role: "BASELINE_LR", modelVersionId: lrId, modelType: "LINEAR_REGRESSION",
      mae: 0.5, rmse: Math.sqrt(0.5), mape: 0, rSquared: 0.98, sampleCount: 2,
      mapeSampleCount: 1, mapeUnavailableReason: null,
      rSquaredUnavailableReason: null,
      predictions: [
        { salesDate: "2026-10-02", predictedUnitsSold: 1 },
        { salesDate: "2026-10-03", predictedUnitsSold: 10 },
      ] },
  ],
};

function client(body: unknown): FastApiMlClient {
  return new FastApiMlClient({
    baseUrl: "http://127.0.0.1:8000",
    internalToken: "test-only-secret",
    fetcher: async (input, init) => {
      assert.equal(String(input), "http://127.0.0.1:8000/evaluate");
      assert.deepEqual(JSON.parse(init?.body as string), request);
      return Response.json(body);
    },
  });
}

test("T-DP-ML-08 [FR-DP-06, BR-DP-04]: validates same holdout, origins and metrics", async () => {
  const result = await client(response).evaluateModels(request);
  assert.equal(result.evaluationLabel, "SIMULATION_BASED");
  assert.equal(result.results[0]?.mae, 2);
  assert.equal(result.results[1]?.mape, 0);
});

test("T-DP-ML-09 [FR-DP-06, NFR-ACC-05]: rejects fabricated or incomparable metrics", async () => {
  for (const bad of [
    { ...response, results: [{ ...response.results[0], mae: 0 }, response.results[1]] },
    { ...response, holdoutFingerprint: "bad" },
    { ...response, originCounts: { ...response.originCounts, SIMULATION_GENERATED: 0 } },
    { ...response, results: [
      { ...response.results[0], predictions: [
        { salesDate: "2026-10-02", predictedUnitsSold: 2 },
        { salesDate: "2026-10-03", predictedUnitsSold: 999 },
      ] }, response.results[1],
    ] },
  ]) {
    await assert.rejects(client(bad).evaluateModels(request),
      (error: unknown) => error instanceof AppError && error.code === "ML_CONTRACT_ERROR");
  }
});
