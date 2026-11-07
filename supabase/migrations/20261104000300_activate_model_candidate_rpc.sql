BEGIN;

CREATE OR REPLACE FUNCTION public.activate_model_candidate_with_audit(
    p_actor_user_id uuid,
    p_candidate_model_version_id uuid,
    p_candidate_evaluation_id uuid,
    p_expected_active_model_version_id uuid,
    p_active_evaluation_id uuid,
    p_verified_artifact_sha256 text,
    p_confirmed boolean
)
RETURNS TABLE (
    model_version_id uuid,
    lifecycle_status text,
    previous_active_model_version_id uuid,
    candidate_mae numeric,
    previous_mae numeric,
    holdout_fingerprint text,
    activated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target public.ml_model_versions%ROWTYPE;
    current_model public.ml_model_versions%ROWTYPE;
    candidate_eval public.model_evaluations%ROWTYPE;
    current_eval public.model_evaluations%ROWTYPE;
    activation_time timestamptz := now();
BEGIN
    IF p_confirmed IS DISTINCT FROM true THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Explicit activation confirmation is required.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.user_profiles AS actor
        WHERE actor.user_id = p_actor_user_id
          AND actor.role = 'SYSTEM_ADMINISTRATOR'
          AND actor.account_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active System Administrator is required.';
    END IF;

    SELECT model.* INTO target
    FROM public.ml_model_versions AS model
    WHERE model.id = p_candidate_model_version_id;
    IF target.id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'The candidate model does not exist.';
    END IF;

    -- Serialise every activation for this category, including first activation.
    PERFORM 1 FROM public.bread_categories AS category
    WHERE category.id = target.bread_category_id
      AND category.is_active = true
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'An active bread category is required.';
    END IF;

    SELECT model.* INTO target
    FROM public.ml_model_versions AS model
    WHERE model.id = p_candidate_model_version_id
    FOR UPDATE;
    SELECT model.* INTO current_model
    FROM public.ml_model_versions AS model
    WHERE model.bread_category_id = target.bread_category_id
      AND model.lifecycle_status = 'ACTIVE'
    FOR UPDATE;

    IF target.lifecycle_status <> 'CANDIDATE'
       OR target.model_type <> 'RANDOM_FOREST'
       OR target.artifact_sha256 IS NULL
       OR target.artifact_sha256 IS DISTINCT FROM p_verified_artifact_sha256
       OR target.feature_version IS DISTINCT FROM 1
       OR target.holdout_start IS NULL
       OR current_model.id IS DISTINCT FROM p_expected_active_model_version_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The candidate or current model changed; evaluate again.';
    END IF;

    SELECT evaluation.* INTO candidate_eval
    FROM public.model_evaluations AS evaluation
    WHERE evaluation.id = p_candidate_evaluation_id
      AND evaluation.model_version_id = target.id
    FOR SHARE;
    IF candidate_eval.id IS NULL
       OR candidate_eval.mae IS NULL
       OR candidate_eval.sample_count <= 0
       OR candidate_eval.holdout_start <= target.training_end
       OR candidate_eval.holdout_start < target.holdout_start
       OR candidate_eval.holdout_fingerprint !~ '^[0-9a-f]{64}$'
       OR NOT EXISTS (
           SELECT 1
           FROM public.ml_model_versions AS baseline
           JOIN public.model_evaluations AS baseline_eval
             ON baseline_eval.model_version_id = baseline.id
           WHERE baseline.training_group_id = target.training_group_id
             AND baseline.model_type = 'LINEAR_REGRESSION'
             AND baseline.lifecycle_status = 'CANDIDATE'
             AND baseline_eval.holdout_fingerprint = candidate_eval.holdout_fingerprint
             AND baseline_eval.holdout_manifest = candidate_eval.holdout_manifest
             AND baseline_eval.holdout_start = candidate_eval.holdout_start
             AND baseline_eval.holdout_end = candidate_eval.holdout_end
             AND baseline_eval.data_origins = candidate_eval.data_origins
             AND baseline_eval.sample_count = candidate_eval.sample_count
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'A complete comparable RF/LR evaluation is required.';
    END IF;

    IF current_model.id IS NULL THEN
        IF p_active_evaluation_id IS NOT NULL THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'No current model exists for this comparison.';
        END IF;
    ELSE
        IF current_model.model_type <> 'RANDOM_FOREST'
           OR current_model.training_end >= candidate_eval.holdout_start
           OR current_model.holdout_start IS NULL
           OR current_model.holdout_start > candidate_eval.holdout_start THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'The current model cannot use this holdout.';
        END IF;

        SELECT evaluation.* INTO current_eval
        FROM public.model_evaluations AS evaluation
        WHERE evaluation.id = p_active_evaluation_id
          AND evaluation.model_version_id = current_model.id
        FOR SHARE;
        IF current_eval.id IS NULL
           OR current_eval.holdout_fingerprint IS DISTINCT FROM candidate_eval.holdout_fingerprint
           OR current_eval.holdout_manifest IS DISTINCT FROM candidate_eval.holdout_manifest
           OR current_eval.holdout_start IS DISTINCT FROM candidate_eval.holdout_start
           OR current_eval.holdout_end IS DISTINCT FROM candidate_eval.holdout_end
           OR current_eval.data_origins IS DISTINCT FROM candidate_eval.data_origins
           OR current_eval.sample_count IS DISTINCT FROM candidate_eval.sample_count
           OR current_eval.mae IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Candidate and current model evaluations are not comparable.';
        END IF;

        IF candidate_eval.mae > current_eval.mae THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001',
                MESSAGE = 'Candidate MAE exceeds the current model MAE on the same holdout.';
        END IF;

        UPDATE public.ml_model_versions AS model
        SET lifecycle_status = 'INACTIVE'
        WHERE model.id = current_model.id;
    END IF;

    UPDATE public.ml_model_versions AS model
    SET lifecycle_status = 'ACTIVE',
        activated_by = p_actor_user_id,
        activated_at = activation_time
    WHERE model.id = target.id;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'MODEL_CANDIDATE_ACTIVATED',
        'MODEL_VERSION', target.id, 'SUCCESS', 'INFO',
        jsonb_build_object(
            'bread_category_id', target.bread_category_id,
            'previous_active_model_version_id', current_model.id,
            'candidate_evaluation_id', candidate_eval.id,
            'active_evaluation_id', current_eval.id,
            'candidate_mae', candidate_eval.mae,
            'previous_mae', current_eval.mae,
            'holdout_fingerprint', candidate_eval.holdout_fingerprint
        )
    );

    RETURN QUERY SELECT
        target.id, 'ACTIVE'::text, current_model.id,
        candidate_eval.mae, current_eval.mae,
        candidate_eval.holdout_fingerprint, activation_time;
END;
$$;

REVOKE ALL ON FUNCTION public.activate_model_candidate_with_audit(
    uuid, uuid, uuid, uuid, uuid, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_model_candidate_with_audit(
    uuid, uuid, uuid, uuid, uuid, text, boolean
) TO service_role;

COMMIT;
