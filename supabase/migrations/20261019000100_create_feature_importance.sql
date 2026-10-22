BEGIN;

CREATE TABLE public.feature_importance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    model_version_id uuid NOT NULL
        REFERENCES public.ml_model_versions(id) ON DELETE RESTRICT,
    feature_name text NOT NULL CHECK (length(trim(feature_name)) > 0),
    importance_score numeric(10,8) NOT NULL
        CHECK (importance_score >= 0 AND importance_score <= 1),
    rank integer NOT NULL CHECK (rank > 0),
    CONSTRAINT feature_importance_model_feature_key
        UNIQUE (model_version_id, feature_name),
    CONSTRAINT feature_importance_model_rank_key
        UNIQUE (model_version_id, rank)
);

-- The unique indexes already support lookups by model version.
ALTER TABLE public.feature_importance ENABLE ROW LEVEL SECURITY;

-- Later ML/Node services calculate and persist the model's importance values.
-- Rank 1 represents the highest importance; ties need deterministic ordering.
-- Importance describes model behavior, not causal effects or accuracy.

COMMIT;
