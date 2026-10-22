BEGIN;

CREATE TABLE public.ml_model_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version integer NOT NULL CHECK (version > 0),
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    model_type text NOT NULL
        CHECK (model_type IN ('RANDOM_FOREST', 'LINEAR_REGRESSION')),
    artifact_key text NOT NULL CHECK (length(trim(artifact_key)) > 0),
    training_start date NOT NULL,
    training_end date NOT NULL,
    lifecycle_status text NOT NULL DEFAULT 'CANDIDATE'
        CHECK (lifecycle_status IN ('CANDIDATE', 'ACTIVE', 'INACTIVE', 'REJECTED')),
    activated_by uuid
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    activated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ml_model_versions_category_version_key
        UNIQUE (bread_category_id, version),
    CONSTRAINT ml_model_versions_training_dates_check
        CHECK (training_start <= training_end),
    CONSTRAINT ml_model_versions_activation_metadata_check
        CHECK (
            (
                lifecycle_status IN ('CANDIDATE', 'REJECTED')
                AND activated_by IS NULL
                AND activated_at IS NULL
            )
            OR
            (
                lifecycle_status IN ('ACTIVE', 'INACTIVE')
                AND activated_by IS NOT NULL
                AND activated_at IS NOT NULL
            )
        )
);

CREATE UNIQUE INDEX idx_ml_model_versions_active_category
    ON public.ml_model_versions (bread_category_id)
    WHERE lifecycle_status = 'ACTIVE';

ALTER TABLE public.ml_model_versions ENABLE ROW LEVEL SECURITY;

-- Later Node model-lifecycle operations must validate ACTIVE administrator
-- permission, training eligibility and comparable holdout evaluations.
-- Operational predictions require an active RANDOM_FOREST model.
-- These checks and atomic activation/restoration are not implemented here.

COMMIT;
