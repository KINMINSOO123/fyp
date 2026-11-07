import assert from "node:assert/strict";
import { test } from "node:test";

test("T-DP-ADMIN-16 [FR-DP-11, FR-DP-12, NFR-SEC-02]: review query returns latest metrics without artifact secrets", async () => {
  process.env.SUPABASE_URL = "http://127.0.0.1:54321";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";
  const { ModelManagementRepo } = await import("./model-management.repo.js");
  const originalFetch = globalThis.fetch;
  const urls: URL[] = [];
  const row = {
    id: "00000000-0000-4000-8000-000000000003",
    version: 2,
    bread_category_id: "00000000-0000-4000-8000-000000000001",
    bread_categories: { name: "Wholemeal Bread" },
    model_type: "RANDOM_FOREST", lifecycle_status: "CANDIDATE",
    created_at: "2026-11-04T00:00:00Z", activated_at: null,
    training_start: "2026-10-05", training_end: "2026-10-28",
    holdout_start: "2026-10-29", feature_version: 1,
    training_group_id: "00000000-0000-4000-8000-000000000006",
    training_origin_counts: { SIMULATION_GENERATED: 24 },
    holdout_origin_counts: { SIMULATION_GENERATED: 6 },
    historical_context_default_count: 0,
    artifact_key: "models/private.joblib",
    artifact_sha256: "a".repeat(64),
    model_evaluations: [{
      id: "00000000-0000-4000-8000-000000000007",
      evaluated_at: "2026-11-04T01:00:00Z",
      holdout_start: "2026-10-29", holdout_end: "2026-11-03",
      holdout_fingerprint: "f".repeat(64),
      evaluation_label: "SIMULATION_BASED",
      data_origins: ["SIMULATION_GENERATED"],
      mae: "2.0000", rmse: "3.0000", mape: null,
      r_squared: "-0.200000", sample_count: 6,
      mape_sample_count: 0,
    }],
  };
  globalThis.fetch = async (input) => {
    urls.push(new URL(String(input)));
    return new Response(JSON.stringify([row]), {
      status: 200,
      headers: { "Content-Type": "application/json",
        "Content-Range": "0-0/1" },
    });
  };
  try {
    const repo = new ModelManagementRepo();
    const page = await repo.listModelReviews(row.bread_category_id, 0, 20);
    assert.equal(page.total, 1);
    assert.equal(page.items[0]?.latestEvaluation?.rSquared, -0.2);
    assert.equal(page.items[0]?.latestEvaluation?.mape, null);
    assert.equal(page.items[0]?.latestEvaluation?.evaluationLabel,
      "SIMULATION_BASED");
    assert.equal("artifactKey" in page.items[0]!, false);
    assert.equal("artifactSha256" in page.items[0]!, false);
    assert.equal(urls[0]?.searchParams.get("model_evaluations.limit"), "1");
    assert.equal(urls[0]?.searchParams.get("bread_category_id"),
      `eq.${row.bread_category_id}`);
    assert(!urls[0]?.searchParams.get("select")?.includes("artifact_key"));
    const detail = await repo.findModelReviewById(row.id);
    assert.equal(detail?.latestEvaluation?.id,
      "00000000-0000-4000-8000-000000000007");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
