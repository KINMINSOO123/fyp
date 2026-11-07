BEGIN;

CREATE OR REPLACE FUNCTION public.record_model_evaluations_with_audit(
    p_actor_user_id uuid,
    p_bread_category_id uuid,
    p_candidate_rf_id uuid,
    p_baseline_lr_id uuid,
    p_current_active_rf_id uuid,
    p_holdout_start date,
    p_holdout_end date,
    p_holdout_manifest jsonb,
    p_holdout_fingerprint text,
    p_data_origins text[],
    p_evaluation_label text,
    p_results jsonb
)
RETURNS TABLE (
    id uuid,
    model_version_id uuid,
    mae numeric,
    holdout_fingerprint text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    candidate public.ml_model_versions%ROWTYPE;
    baseline public.ml_model_versions%ROWTYPE;
    active_model public.ml_model_versions%ROWTYPE;
    result_item jsonb;
    result_role text;
    result_model_id uuid;
    inserted_id uuid;
    inserted_ids uuid[] := ARRAY[]::uuid[];
    seen_candidate boolean := false;
    seen_baseline boolean := false;
    seen_active boolean := false;
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

    SELECT model.* INTO candidate
    FROM public.ml_model_versions AS model
    WHERE model.id = p_candidate_rf_id
    FOR UPDATE;
    SELECT model.* INTO baseline
    FROM public.ml_model_versions AS model
    WHERE model.id = p_baseline_lr_id
    FOR UPDATE;
    SELECT model.* INTO active_model
    FROM public.ml_model_versions AS model
    WHERE model.bread_category_id = p_bread_category_id
      AND model.lifecycle_status = 'ACTIVE'
    FOR UPDATE;

    IF candidate.id IS NULL OR baseline.id IS NULL
       OR candidate.bread_category_id <> p_bread_category_id
       OR baseline.bread_category_id <> p_bread_category_id
       OR candidate.model_type <> 'RANDOM_FOREST'
       OR baseline.model_type <> 'LINEAR_REGRESSION'
       OR candidate.lifecycle_status <> 'CANDIDATE'
       OR baseline.lifecycle_status <> 'CANDIDATE'
       OR candidate.training_group_id IS NULL
       OR candidate.training_group_id IS DISTINCT FROM baseline.training_group_id
       OR candidate.training_fingerprint IS DISTINCT FROM baseline.training_fingerprint
       OR candidate.training_end IS DISTINCT FROM baseline.training_end
       OR candidate.holdout_start IS NULL
       OR baseline.holdout_start IS NULL
       OR candidate.holdout_start > p_holdout_start
       OR baseline.holdout_start > p_holdout_start
       OR active_model.id IS DISTINCT FROM p_current_active_rf_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The model comparison is stale or invalid.';
    END IF;

    IF active_model.id IS NOT NULL AND (
        active_model.model_type <> 'RANDOM_FOREST'
        OR active_model.training_end >= p_holdout_start
        OR active_model.holdout_start > p_holdout_start
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The current model used the proposed holdout period.';
    END IF;

    IF p_holdout_start IS NULL OR p_holdout_end IS NULL
       OR p_holdout_start > p_holdout_end
       OR p_holdout_start <= candidate.training_end
       OR p_holdout_manifest IS NULL
       OR jsonb_typeof(p_holdout_manifest) <> 'object'
       OR p_holdout_manifest->>'breadCategoryId' IS DISTINCT FROM p_bread_category_id::text
       OR p_holdout_manifest->>'holdoutStart' IS DISTINCT FROM p_holdout_start::text
       OR p_holdout_fingerprint IS NULL
       OR p_holdout_fingerprint !~ '^[0-9a-f]{64}$'
       OR p_results IS NULL OR jsonb_typeof(p_results) <> 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Invalid holdout evaluation metadata.';
    END IF;

    IF jsonb_array_length(p_results) < 2
       OR jsonb_array_length(p_results) > 3 THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The evaluation model count is invalid.';
    END IF;

    FOR result_item IN
        SELECT entry.item FROM jsonb_array_elements(p_results) AS entry(item)
    LOOP
        result_role := result_item->>'role';
        result_model_id := (result_item->>'modelVersionId')::uuid;
        IF result_role = 'CANDIDATE_RF' AND NOT seen_candidate
           AND result_model_id = candidate.id THEN
            seen_candidate := true;
        ELSIF result_role = 'BASELINE_LR' AND NOT seen_baseline
           AND result_model_id = baseline.id THEN
            seen_baseline := true;
        ELSIF result_role = 'CURRENT_ACTIVE_RF' AND NOT seen_active
           AND active_model.id IS NOT NULL
           AND result_model_id = active_model.id THEN
            seen_active := true;
        ELSE
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Unexpected or duplicate evaluation model.';
        END IF;

        INSERT INTO public.model_evaluations AS evaluation (
            model_version_id, holdout_start, holdout_end,
            holdout_manifest, holdout_fingerprint,
            data_origins, evaluation_label,
            mae, rmse, mape, r_squared,
            sample_count, mape_sample_count
        ) VALUES (
            result_model_id, p_holdout_start, p_holdout_end,
            p_holdout_manifest, p_holdout_fingerprint,
            p_data_origins, p_evaluation_label,
            (result_item->>'mae')::numeric,
            (result_item->>'rmse')::numeric,
            (result_item->>'mape')::numeric,
            (result_item->>'rSquared')::numeric,
            (result_item->>'sampleCount')::integer,
            (result_item->>'mapeSampleCount')::integer
        ) RETURNING evaluation.id INTO inserted_id;
        inserted_ids := array_append(inserted_ids, inserted_id);
    END LOOP;

    IF NOT seen_candidate OR NOT seen_baseline
       OR (active_model.id IS NOT NULL AND NOT seen_active)
       OR (active_model.id IS NULL AND seen_active) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The same-dataset comparison is incomplete.';
    END IF;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'MODEL_EVALUATION_RECORDED',
        'MODEL_VERSION', candidate.id, 'SUCCESS', 'INFO',
        jsonb_build_object(
            'bread_category_id', p_bread_category_id,
            'holdout_fingerprint', p_holdout_fingerprint,
            'baseline_model_version_id', baseline.id,
            'active_model_version_id', active_model.id,
            'evaluation_ids', inserted_ids
        )
    );

    RETURN QUERY
    SELECT evaluation.id, evaluation.model_version_id,
           evaluation.mae, evaluation.holdout_fingerprint
    FROM public.model_evaluations AS evaluation
    WHERE evaluation.id = ANY(inserted_ids)
    ORDER BY evaluation.model_version_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_model_evaluations_with_audit(
    uuid, uuid, uuid, uuid, uuid, date, date, jsonb, text, text[], text, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_model_evaluations_with_audit(
    uuid, uuid, uuid, uuid, uuid, date, date, jsonb, text, text[], text, jsonb
) TO service_role;

COMMIT;
