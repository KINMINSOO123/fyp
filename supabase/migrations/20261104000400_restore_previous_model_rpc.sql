BEGIN;

CREATE OR REPLACE FUNCTION public.restore_previous_model_with_audit(
    p_actor_user_id uuid,
    p_previous_model_version_id uuid,
    p_expected_active_model_version_id uuid,
    p_verified_artifact_sha256 text,
    p_confirmed boolean
)
RETURNS TABLE (
    model_version_id uuid,
    lifecycle_status text,
    previous_active_model_version_id uuid,
    restored_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target public.ml_model_versions%ROWTYPE;
    current_model public.ml_model_versions%ROWTYPE;
    restoration_time timestamptz := now();
BEGIN
    IF p_confirmed IS DISTINCT FROM true THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Explicit restoration confirmation is required.';
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
    WHERE model.id = p_previous_model_version_id;
    IF target.id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'The previous model does not exist.';
    END IF;

    -- The category lock serialises restoration with candidate activation.
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
    WHERE model.id = p_previous_model_version_id
    FOR UPDATE;
    SELECT model.* INTO current_model
    FROM public.ml_model_versions AS model
    WHERE model.bread_category_id = target.bread_category_id
      AND model.lifecycle_status = 'ACTIVE'
    FOR UPDATE;

    IF target.lifecycle_status <> 'INACTIVE'
       OR target.model_type <> 'RANDOM_FOREST'
       OR target.activated_by IS NULL
       OR target.activated_at IS NULL
       OR target.artifact_sha256 IS NULL
       OR target.artifact_sha256 IS DISTINCT FROM p_verified_artifact_sha256
       OR target.feature_version IS DISTINCT FROM 1
       OR target.holdout_start IS NULL
       OR current_model.id IS NULL
       OR current_model.id IS DISTINCT FROM p_expected_active_model_version_id
       OR current_model.model_type <> 'RANDOM_FOREST'
       OR NOT EXISTS (
           SELECT 1 FROM public.model_evaluations AS evaluation
           WHERE evaluation.model_version_id = target.id
             AND evaluation.holdout_start > target.training_end
             AND evaluation.sample_count > 0
             AND evaluation.mae IS NOT NULL
             AND evaluation.holdout_fingerprint ~ '^[0-9a-f]{64}$'
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The previous or current model changed or is invalid.';
    END IF;

    UPDATE public.ml_model_versions AS model
    SET lifecycle_status = 'INACTIVE'
    WHERE model.id = current_model.id;

    UPDATE public.ml_model_versions AS model
    SET lifecycle_status = 'ACTIVE',
        activated_by = p_actor_user_id,
        activated_at = restoration_time
    WHERE model.id = target.id;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'MODEL_VERSION_RESTORED',
        'MODEL_VERSION', target.id, 'SUCCESS', 'INFO',
        jsonb_build_object(
            'bread_category_id', target.bread_category_id,
            'replaced_model_version_id', current_model.id,
            'restored_model_version_id', target.id,
            'previous_activation_at', target.activated_at
        )
    );

    RETURN QUERY SELECT
        target.id, 'ACTIVE'::text, current_model.id, restoration_time;
END;
$$;

REVOKE ALL ON FUNCTION public.restore_previous_model_with_audit(
    uuid, uuid, uuid, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_previous_model_with_audit(
    uuid, uuid, uuid, text, boolean
) TO service_role;

COMMIT;
