BEGIN;

ALTER TABLE public.ml_model_versions
    ADD COLUMN training_group_id uuid,
    ADD COLUMN holdout_start date,
    ADD COLUMN training_fingerprint text,
    ADD COLUMN artifact_sha256 text,
    ADD COLUMN feature_version integer,
    ADD COLUMN training_origin_counts jsonb,
    ADD COLUMN holdout_origin_counts jsonb,
    ADD COLUMN historical_context_default_count integer;

ALTER TABLE public.ml_model_versions
    ADD CONSTRAINT ml_model_versions_retained_metadata_check
    CHECK (
        (holdout_start IS NULL OR holdout_start > training_end)
        AND (training_fingerprint IS NULL OR training_fingerprint ~ '^[0-9a-f]{64}$')
        AND (artifact_sha256 IS NULL OR artifact_sha256 ~ '^[0-9a-f]{64}$')
        AND (feature_version IS NULL OR feature_version > 0)
        AND (training_origin_counts IS NULL OR jsonb_typeof(training_origin_counts) = 'object')
        AND (holdout_origin_counts IS NULL OR jsonb_typeof(holdout_origin_counts) = 'object')
        AND (historical_context_default_count IS NULL
             OR historical_context_default_count >= 0)
    );

CREATE UNIQUE INDEX idx_ml_model_versions_training_group_type
    ON public.ml_model_versions (training_group_id, model_type)
    WHERE training_group_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_model_candidates_with_audit(
    p_actor_user_id uuid,
    p_bread_category_id uuid,
    p_rf_model_version_id uuid,
    p_lr_model_version_id uuid,
    p_rf_artifact_key text,
    p_lr_artifact_key text,
    p_rf_artifact_sha256 text,
    p_lr_artifact_sha256 text,
    p_training_start date,
    p_training_end date,
    p_holdout_start date,
    p_training_fingerprint text,
    p_feature_version integer,
    p_training_origin_counts jsonb,
    p_holdout_origin_counts jsonb,
    p_historical_context_default_count integer
)
RETURNS TABLE (
    id uuid,
    version integer,
    model_type text,
    lifecycle_status text,
    training_group_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    next_version integer;
    new_group_id uuid := gen_random_uuid();
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.user_profiles AS actor
        WHERE actor.user_id = p_actor_user_id
          AND actor.role = 'SYSTEM_ADMINISTRATOR'
          AND actor.account_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active System Administrator is required.';
    END IF;

    PERFORM 1 FROM public.bread_categories AS category
    WHERE category.id = p_bread_category_id AND category.is_active = true
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'An active bread category is required.';
    END IF;

    IF p_rf_model_version_id = p_lr_model_version_id
       OR p_training_start IS NULL OR p_training_end IS NULL
       OR p_holdout_start IS NULL
       OR p_training_start > p_training_end
       OR p_holdout_start <= p_training_end
       OR p_feature_version IS DISTINCT FROM 1
       OR p_training_fingerprint IS NULL
       OR p_training_fingerprint !~ '^[0-9a-f]{64}$'
       OR p_rf_artifact_sha256 IS NULL
       OR p_rf_artifact_sha256 !~ '^[0-9a-f]{64}$'
       OR p_lr_artifact_sha256 IS NULL
       OR p_lr_artifact_sha256 !~ '^[0-9a-f]{64}$'
       OR p_rf_artifact_key IS NULL OR length(trim(p_rf_artifact_key)) = 0
       OR p_lr_artifact_key IS NULL OR length(trim(p_lr_artifact_key)) = 0
       OR p_training_origin_counts IS NULL
       OR jsonb_typeof(p_training_origin_counts) <> 'object'
       OR p_holdout_origin_counts IS NULL
       OR jsonb_typeof(p_holdout_origin_counts) <> 'object'
       OR p_historical_context_default_count IS NULL
       OR p_historical_context_default_count < 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Invalid candidate metadata.';
    END IF;

    SELECT coalesce(max(existing.version), 0) + 1 INTO next_version
    FROM public.ml_model_versions AS existing
    WHERE existing.bread_category_id = p_bread_category_id;

    INSERT INTO public.ml_model_versions (
        id, version, bread_category_id, model_type, artifact_key,
        artifact_sha256, training_start, training_end, holdout_start,
        training_fingerprint, training_group_id, feature_version,
        training_origin_counts, holdout_origin_counts,
        historical_context_default_count,
        lifecycle_status
    ) VALUES
    (p_rf_model_version_id, next_version, p_bread_category_id,
     'RANDOM_FOREST', p_rf_artifact_key, p_rf_artifact_sha256,
     p_training_start, p_training_end, p_holdout_start,
     p_training_fingerprint, new_group_id, p_feature_version,
     p_training_origin_counts, p_holdout_origin_counts,
     p_historical_context_default_count, 'CANDIDATE'),
    (p_lr_model_version_id, next_version + 1, p_bread_category_id,
     'LINEAR_REGRESSION', p_lr_artifact_key, p_lr_artifact_sha256,
     p_training_start, p_training_end, p_holdout_start,
     p_training_fingerprint, new_group_id, p_feature_version,
     p_training_origin_counts, p_holdout_origin_counts,
     p_historical_context_default_count, 'CANDIDATE');

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'MODEL_CANDIDATES_CREATED',
        'MODEL_TRAINING_GROUP', new_group_id, 'SUCCESS', 'INFO',
        jsonb_build_object(
            'bread_category_id', p_bread_category_id,
            'rf_model_version_id', p_rf_model_version_id,
            'lr_model_version_id', p_lr_model_version_id,
            'holdout_start', p_holdout_start,
            'training_fingerprint', p_training_fingerprint,
            'training_origin_counts', p_training_origin_counts,
            'holdout_origin_counts', p_holdout_origin_counts
        )
    );

    RETURN QUERY
    SELECT model.id, model.version, model.model_type,
           model.lifecycle_status, model.training_group_id
    FROM public.ml_model_versions AS model
    WHERE model.id IN (p_rf_model_version_id, p_lr_model_version_id)
    ORDER BY model.version;
END;
$$;

REVOKE ALL ON FUNCTION public.create_model_candidates_with_audit(
    uuid, uuid, uuid, uuid, text, text, text, text,
    date, date, date, text, integer, jsonb, jsonb, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_model_candidates_with_audit(
    uuid, uuid, uuid, uuid, text, text, text, text,
    date, date, date, text, integer, jsonb, jsonb, integer
) TO service_role;

COMMIT;
