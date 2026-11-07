import { supabaseAdmin } from "../../config/supabase.js";
import { AppError } from "../../shared/AppError.js";
import type {
  TrainingCandidateResponseDto,
} from "./fast-api-ml.client.js";
import type { EvaluationResponseDto } from "./model-evaluation.dto.js";

export type ModelType = "RANDOM_FOREST" | "LINEAR_REGRESSION";
export type ModelStatus = "CANDIDATE" | "ACTIVE" | "INACTIVE" | "REJECTED";

export interface StoredModelVersion {
  id: string;
  version: number;
  breadCategoryId: string;
  modelType: ModelType;
  artifactKey: string;
  artifactSha256: string | null;
  trainingStart: string;
  trainingEnd: string;
  holdoutStart: string | null;
  trainingFingerprint: string | null;
  trainingGroupId: string | null;
  lifecycleStatus: ModelStatus;
}

interface ModelRow {
  id: string;
  version: number;
  bread_category_id: string;
  model_type: ModelType;
  artifact_key: string;
  artifact_sha256: string | null;
  training_start: string;
  training_end: string;
  holdout_start: string | null;
  training_fingerprint: string | null;
  training_group_id: string | null;
  lifecycle_status: ModelStatus;
}

const modelColumns = "id, version, bread_category_id, model_type, artifact_key, artifact_sha256, training_start, training_end, holdout_start, training_fingerprint, training_group_id, lifecycle_status";

function mapModel(row: ModelRow): StoredModelVersion {
  return {
    id: row.id,
    version: row.version,
    breadCategoryId: row.bread_category_id,
    modelType: row.model_type,
    artifactKey: row.artifact_key,
    artifactSha256: row.artifact_sha256,
    trainingStart: row.training_start,
    trainingEnd: row.training_end,
    holdoutStart: row.holdout_start,
    trainingFingerprint: row.training_fingerprint,
    trainingGroupId: row.training_group_id,
    lifecycleStatus: row.lifecycle_status,
  };
}

export interface PersistedCandidate {
  id: string;
  version: number;
  modelType: ModelType;
  lifecycleStatus: "CANDIDATE";
  trainingGroupId: string;
}

export interface PersistedEvaluation {
  id: string;
  modelVersionId: string;
  mae: number;
  holdoutFingerprint: string;
}

export interface StoredEvaluation {
  id: string;
  modelVersionId: string;
  mae: number;
  holdoutFingerprint: string;
}

export interface ActivationResult {
  modelVersionId: string;
  lifecycleStatus: "ACTIVE";
  previousActiveModelVersionId: string | null;
  candidateMae: number;
  previousMae: number | null;
  holdoutFingerprint: string;
  activatedAt: string;
}

export interface RestorationResult {
  modelVersionId: string;
  lifecycleStatus: "ACTIVE";
  previousActiveModelVersionId: string;
  restoredAt: string;
}

export interface ModelEvaluationReview {
  id: string;
  evaluatedAt: string;
  holdoutStart: string;
  holdoutEnd: string;
  holdoutFingerprint: string;
  evaluationLabel: string;
  dataOrigins: string[];
  mae: number;
  rmse: number;
  mape: number | null;
  rSquared: number | null;
  sampleCount: number;
  mapeSampleCount: number;
}

export interface ModelVersionReview {
  id: string;
  version: number;
  breadCategoryId: string;
  breadCategoryName: string;
  modelType: ModelType;
  lifecycleStatus: ModelStatus;
  createdAt: string;
  activatedAt: string | null;
  trainingStart: string;
  trainingEnd: string;
  holdoutStart: string | null;
  trainingGroupId: string | null;
  featureVersion: number | null;
  trainingOriginCounts: Record<string, number> | null;
  holdoutOriginCounts: Record<string, number> | null;
  historicalContextDefaultCount: number | null;
  latestEvaluation: ModelEvaluationReview | null;
}

export interface TrainingCategory {
  id: string;
  name: string;
  displayOrder: number;
}

interface ModelReviewRow {
  id: string;
  version: number;
  bread_category_id: string;
  bread_categories: { name: string };
  model_type: ModelType;
  lifecycle_status: ModelStatus;
  created_at: string;
  activated_at: string | null;
  training_start: string;
  training_end: string;
  holdout_start: string | null;
  training_group_id: string | null;
  feature_version: number | null;
  training_origin_counts: Record<string, number> | null;
  holdout_origin_counts: Record<string, number> | null;
  historical_context_default_count: number | null;
  model_evaluations: Array<{
    id: string;
    evaluated_at: string;
    holdout_start: string;
    holdout_end: string;
    holdout_fingerprint: string;
    evaluation_label: string;
    data_origins: string[];
    mae: number | string;
    rmse: number | string;
    mape: number | string | null;
    r_squared: number | string | null;
    sample_count: number;
    mape_sample_count: number;
  }>;
}

const reviewColumns = `id, version, bread_category_id, model_type,
  lifecycle_status, created_at, activated_at, training_start, training_end,
  holdout_start, training_group_id, feature_version, training_origin_counts,
  holdout_origin_counts, historical_context_default_count,
  bread_categories(name),
  model_evaluations(id, evaluated_at, holdout_start, holdout_end,
    holdout_fingerprint, evaluation_label, data_origins, mae, rmse, mape,
    r_squared, sample_count, mape_sample_count)`;

function mapReview(row: ModelReviewRow): ModelVersionReview {
  const latest = row.model_evaluations?.[0];
  return {
    id: row.id,
    version: row.version,
    breadCategoryId: row.bread_category_id,
    breadCategoryName: row.bread_categories.name,
    modelType: row.model_type,
    lifecycleStatus: row.lifecycle_status,
    createdAt: row.created_at,
    activatedAt: row.activated_at,
    trainingStart: row.training_start,
    trainingEnd: row.training_end,
    holdoutStart: row.holdout_start,
    trainingGroupId: row.training_group_id,
    featureVersion: row.feature_version,
    trainingOriginCounts: row.training_origin_counts,
    holdoutOriginCounts: row.holdout_origin_counts,
    historicalContextDefaultCount: row.historical_context_default_count,
    latestEvaluation: latest ? {
      id: latest.id,
      evaluatedAt: latest.evaluated_at,
      holdoutStart: latest.holdout_start,
      holdoutEnd: latest.holdout_end,
      holdoutFingerprint: latest.holdout_fingerprint,
      evaluationLabel: latest.evaluation_label,
      dataOrigins: latest.data_origins,
      mae: Number(latest.mae),
      rmse: Number(latest.rmse),
      mape: latest.mape === null ? null : Number(latest.mape),
      rSquared: latest.r_squared === null ? null : Number(latest.r_squared),
      sampleCount: latest.sample_count,
      mapeSampleCount: latest.mape_sample_count,
    } : null,
  };
}

export class ModelManagementRepo {
  async listTrainingCategories(): Promise<TrainingCategory[]> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("id, name, display_order").eq("is_active", true)
      .order("display_order", { ascending: true })
      .order("id", { ascending: true });
    if (error || !data) throw new Error("Unable to load active bread categories.");
    return data.map((row) => ({
      id: row.id, name: row.name, displayOrder: row.display_order,
    }));
  }

  async listModelReviews(
    categoryId: string | null,
    offset: number,
    pageSize: number,
  ): Promise<{ items: ModelVersionReview[]; total: number }> {
    let query = supabaseAdmin.from("ml_model_versions")
      .select(reviewColumns, { count: "exact" });
    if (categoryId) query = query.eq("bread_category_id", categoryId);
    const { data, count, error } = await query
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .order("evaluated_at", {
        referencedTable: "model_evaluations", ascending: false,
      })
      .order("id", {
        referencedTable: "model_evaluations", ascending: false,
      })
      .limit(1, { referencedTable: "model_evaluations" })
      .range(offset, offset + pageSize - 1);
    if (error || !data || count === null) {
      throw new Error("Unable to load model version history.");
    }
    return { items: (data as unknown as ModelReviewRow[]).map(mapReview),
      total: count };
  }

  async findModelReviewById(id: string): Promise<ModelVersionReview | null> {
    const { data, error } = await supabaseAdmin.from("ml_model_versions")
      .select(reviewColumns).eq("id", id)
      .order("evaluated_at", {
        referencedTable: "model_evaluations", ascending: false,
      })
      .order("id", {
        referencedTable: "model_evaluations", ascending: false,
      })
      .limit(1, { referencedTable: "model_evaluations" })
      .maybeSingle();
    if (error) throw new Error("Unable to load the model review.");
    return data ? mapReview(data as unknown as ModelReviewRow) : null;
  }

  async assertStorageReady(): Promise<void> {
    const { error } = await supabaseAdmin.from("ml_model_versions")
      .select("training_group_id, holdout_start, training_fingerprint, artifact_sha256, feature_version")
      .limit(1);
    if (error) {
      throw new AppError(503, "MODEL_SCHEMA_NOT_READY",
        "The model-management database migration is not available.");
    }
  }

  async getBakeryTimezone(): Promise<string> {
    const { data, error } = await supabaseAdmin.from("bakery_settings")
      .select("timezone").eq("singleton_guard", true).single();
    if (error || !data || typeof data.timezone !== "string") {
      throw new Error("Bakery timezone is not configured.");
    }
    return data.timezone;
  }

  async isActiveCategory(categoryId: string): Promise<boolean> {
    const { data, error } = await supabaseAdmin.from("bread_categories")
      .select("is_active").eq("id", categoryId).maybeSingle();
    if (error) throw new Error("Unable to load the bread category.");
    return data?.is_active === true;
  }

  async findModelById(id: string): Promise<StoredModelVersion | null> {
    const { data, error } = await supabaseAdmin.from("ml_model_versions")
      .select(modelColumns).eq("id", id).maybeSingle();
    if (error) throw new Error("Unable to load the model version.");
    return data ? mapModel(data as ModelRow) : null;
  }

  async findBaseline(groupId: string): Promise<StoredModelVersion | null> {
    const { data, error } = await supabaseAdmin.from("ml_model_versions")
      .select(modelColumns).eq("training_group_id", groupId)
      .eq("model_type", "LINEAR_REGRESSION").limit(2);
    if (error) throw new Error("Unable to load the baseline model.");
    if (data.length > 1) throw new Error("Training group has duplicate LR models.");
    return data[0] ? mapModel(data[0] as ModelRow) : null;
  }

  async findActive(categoryId: string): Promise<StoredModelVersion | null> {
    const { data, error } = await supabaseAdmin.from("ml_model_versions")
      .select(modelColumns).eq("bread_category_id", categoryId)
      .eq("lifecycle_status", "ACTIVE").maybeSingle();
    if (error) throw new Error("Unable to load the current model.");
    return data ? mapModel(data as ModelRow) : null;
  }

  async findEvaluationById(id: string): Promise<StoredEvaluation | null> {
    const { data, error } = await supabaseAdmin.from("model_evaluations")
      .select("id, model_version_id, mae, holdout_fingerprint")
      .eq("id", id).maybeSingle();
    if (error) throw new Error("Unable to load the model evaluation.");
    return data ? {
      id: data.id,
      modelVersionId: data.model_version_id,
      mae: Number(data.mae),
      holdoutFingerprint: data.holdout_fingerprint,
    } : null;
  }

  async findComparableEvaluation(
    modelVersionId: string,
    fingerprint: string,
  ): Promise<StoredEvaluation | null> {
    const { data, error } = await supabaseAdmin.from("model_evaluations")
      .select("id, model_version_id, mae, holdout_fingerprint")
      .eq("model_version_id", modelVersionId)
      .eq("holdout_fingerprint", fingerprint)
      .order("evaluated_at", { ascending: false })
      .limit(1).maybeSingle();
    if (error) throw new Error("Unable to load the comparable evaluation.");
    return data ? {
      id: data.id,
      modelVersionId: data.model_version_id,
      mae: Number(data.mae),
      holdoutFingerprint: data.holdout_fingerprint,
    } : null;
  }

  async hasValidEvaluation(
    modelVersionId: string,
    trainingEnd: string,
  ): Promise<boolean> {
    const { data, error } = await supabaseAdmin.from("model_evaluations")
      .select("id").eq("model_version_id", modelVersionId)
      .gt("holdout_start", trainingEnd).gt("sample_count", 0)
      .gte("mae", 0).limit(1);
    if (error) throw new Error("Unable to load the retained model evaluation.");
    return data.length > 0;
  }

  async createCandidates(
    actorUserId: string,
    categoryId: string,
    result: TrainingCandidateResponseDto,
  ): Promise<PersistedCandidate[]> {
    const rf = result.candidates[0];
    const lr = result.candidates[1];
    if (!rf || !lr) throw new Error("The candidate pair is incomplete.");
    const { data, error } = await supabaseAdmin.rpc(
      "create_model_candidates_with_audit", {
        p_actor_user_id: actorUserId,
        p_bread_category_id: categoryId,
        p_rf_model_version_id: rf.modelVersionId,
        p_lr_model_version_id: lr.modelVersionId,
        p_rf_artifact_key: rf.artifactKey,
        p_lr_artifact_key: lr.artifactKey,
        p_rf_artifact_sha256: rf.sha256,
        p_lr_artifact_sha256: lr.sha256,
        p_training_start: result.trainingStart,
        p_training_end: result.trainingEnd,
        p_holdout_start: result.holdoutStart,
        p_training_fingerprint: result.trainingFingerprint,
        p_feature_version: result.featureVersion,
        p_training_origin_counts: result.trainingOrigins,
        p_holdout_origin_counts: result.holdoutOrigins,
        p_historical_context_default_count: result.historicalContextDefaultCount,
      },
    );
    if (error || !Array.isArray(data)) {
      if (error?.code === "42501") {
        throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      }
      throw new Error("Unable to store the candidate model pair.");
    }
    const rows = data as Array<{
      id: string; version: number; model_type: ModelType;
      lifecycle_status: "CANDIDATE"; training_group_id: string;
    }>;
    if (rows.length !== 2 || rows[0]?.id !== rf.modelVersionId ||
        rows[1]?.id !== lr.modelVersionId ||
        rows.some((row) => row.lifecycle_status !== "CANDIDATE")) {
      throw new Error("Candidate persistence returned an invalid result.");
    }
    return rows.map((row) => ({
      id: row.id,
      version: row.version,
      modelType: row.model_type,
      lifecycleStatus: row.lifecycle_status,
      trainingGroupId: row.training_group_id,
    }));
  }

  async recordEvaluations(
    actorUserId: string,
    candidate: StoredModelVersion,
    baseline: StoredModelVersion,
    activeId: string | null,
    result: EvaluationResponseDto,
  ): Promise<PersistedEvaluation[]> {
    const { data, error } = await supabaseAdmin.rpc(
      "record_model_evaluations_with_audit", {
        p_actor_user_id: actorUserId,
        p_bread_category_id: candidate.breadCategoryId,
        p_candidate_rf_id: candidate.id,
        p_baseline_lr_id: baseline.id,
        p_current_active_rf_id: activeId,
        p_holdout_start: result.holdoutStart,
        p_holdout_end: result.holdoutEnd,
        p_holdout_manifest: result.holdoutManifest,
        p_holdout_fingerprint: result.holdoutFingerprint,
        p_data_origins: result.dataOrigins,
        p_evaluation_label: result.evaluationLabel,
        p_results: result.results,
      },
    );
    if (error || !Array.isArray(data)) {
      if (error?.code === "42501") {
        throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      }
      if (error?.code === "22023") {
        throw new AppError(409, "MODEL_COMPARISON_STALE",
          "The model comparison changed; evaluate again.");
      }
      if (error?.code === "PGRST202") {
        throw new AppError(503, "MODEL_SCHEMA_NOT_READY",
          "The model evaluation database migration is not available.");
      }
      throw new Error("Unable to store model evaluations.");
    }
    const rows = data as Array<{
      id: string; model_version_id: string; mae: number | string;
      holdout_fingerprint: string;
    }>;
    const expectedIds = new Set(result.results.map((item) => item.modelVersionId));
    if (rows.length !== expectedIds.size || rows.some((row) =>
      !expectedIds.has(row.model_version_id) ||
      row.holdout_fingerprint !== result.holdoutFingerprint)) {
      throw new Error("Evaluation persistence returned an invalid result.");
    }
    return rows.map((row) => ({
      id: row.id,
      modelVersionId: row.model_version_id,
      mae: Number(row.mae),
      holdoutFingerprint: row.holdout_fingerprint,
    }));
  }

  async activateCandidate(
    actorUserId: string,
    candidateModelVersionId: string,
    candidateEvaluationId: string,
    expectedActiveModelVersionId: string | null,
    activeEvaluationId: string | null,
    verifiedArtifactSha256: string,
  ): Promise<ActivationResult> {
    const { data, error } = await supabaseAdmin.rpc(
      "activate_model_candidate_with_audit", {
        p_actor_user_id: actorUserId,
        p_candidate_model_version_id: candidateModelVersionId,
        p_candidate_evaluation_id: candidateEvaluationId,
        p_expected_active_model_version_id: expectedActiveModelVersionId,
        p_active_evaluation_id: activeEvaluationId,
        p_verified_artifact_sha256: verifiedArtifactSha256,
        p_confirmed: true,
      },
    );
    if (error || !Array.isArray(data)) {
      if (error?.code === "42501") {
        throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      }
      if (error?.code === "P0001") {
        throw new AppError(409, "MODEL_MAE_WORSE",
          "Candidate MAE exceeds the current model MAE on the same holdout.");
      }
      if (error?.code === "P0002") {
        throw new AppError(404, "MODEL_NOT_FOUND", "The candidate model was not found.");
      }
      if (error?.code === "22023") {
        throw new AppError(409, "MODEL_ACTIVATION_STALE",
          "Model or evaluation state changed; review and evaluate again.");
      }
      if (error?.code === "PGRST202") {
        throw new AppError(503, "MODEL_SCHEMA_NOT_READY",
          "The model activation database migration is not available.");
      }
      throw new Error("Unable to activate the model candidate.");
    }
    const row = data[0] as {
      model_version_id: string;
      lifecycle_status: string;
      previous_active_model_version_id: string | null;
      candidate_mae: number | string;
      previous_mae: number | string | null;
      holdout_fingerprint: string;
      activated_at: string;
    } | undefined;
    if (data.length !== 1 || !row ||
        row.model_version_id !== candidateModelVersionId ||
        row.lifecycle_status !== "ACTIVE" ||
        row.previous_active_model_version_id !== expectedActiveModelVersionId) {
      throw new Error("Activation returned an invalid result.");
    }
    return {
      modelVersionId: row.model_version_id,
      lifecycleStatus: "ACTIVE",
      previousActiveModelVersionId: row.previous_active_model_version_id,
      candidateMae: Number(row.candidate_mae),
      previousMae: row.previous_mae === null ? null : Number(row.previous_mae),
      holdoutFingerprint: row.holdout_fingerprint,
      activatedAt: row.activated_at,
    };
  }

  async restorePreviousModel(
    actorUserId: string,
    previousModelVersionId: string,
    expectedActiveModelVersionId: string,
    verifiedArtifactSha256: string,
  ): Promise<RestorationResult> {
    const { data, error } = await supabaseAdmin.rpc(
      "restore_previous_model_with_audit", {
        p_actor_user_id: actorUserId,
        p_previous_model_version_id: previousModelVersionId,
        p_expected_active_model_version_id: expectedActiveModelVersionId,
        p_verified_artifact_sha256: verifiedArtifactSha256,
        p_confirmed: true,
      },
    );
    if (error || !Array.isArray(data)) {
      if (error?.code === "42501") {
        throw new AppError(403, "FORBIDDEN", "Administrator permission is required.");
      }
      if (error?.code === "P0002") {
        throw new AppError(404, "MODEL_NOT_FOUND", "The previous model was not found.");
      }
      if (error?.code === "22023") {
        throw new AppError(409, "MODEL_RESTORATION_STALE",
          "Model state changed; review the previous and current versions again.");
      }
      if (error?.code === "PGRST202") {
        throw new AppError(503, "MODEL_SCHEMA_NOT_READY",
          "The model restoration database migration is not available.");
      }
      throw new Error("Unable to restore the previous model.");
    }
    const row = data[0] as {
      model_version_id: string;
      lifecycle_status: string;
      previous_active_model_version_id: string;
      restored_at: string;
    } | undefined;
    if (data.length !== 1 || !row ||
        row.model_version_id !== previousModelVersionId ||
        row.lifecycle_status !== "ACTIVE" ||
        row.previous_active_model_version_id !== expectedActiveModelVersionId ||
        typeof row.restored_at !== "string") {
      throw new Error("Restoration returned an invalid result.");
    }
    return {
      modelVersionId: row.model_version_id,
      lifecycleStatus: "ACTIVE",
      previousActiveModelVersionId: row.previous_active_model_version_id,
      restoredAt: row.restored_at,
    };
  }
}
