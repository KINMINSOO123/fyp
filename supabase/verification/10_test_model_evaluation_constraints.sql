-- Run the WHOLE file as postgres. Requires an ACTIVE SYSTEM_ADMINISTRATOR.
-- All fixtures roll back; no real model artifact is created or activated.
-- Tests storage only, NOT training eligibility, metric calculations, untouched
-- chronological holdout validation, same-dataset comparison or higher-MAE rejection.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    active_model uuid := gen_random_uuid();
    candidate_model uuid := gen_random_uuid();
    evaluation_id_value uuid;
    administrator_id uuid;
    next_order integer;
    rejected boolean;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT user_id INTO administrator_id FROM public.user_profiles
    WHERE role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
    ORDER BY user_id LIMIT 1;
    IF administrator_id IS NULL THEN RAISE EXCEPTION 'An ACTIVE SYSTEM_ADMINISTRATOR is required'; END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback model test ' || category_id::text, next_order);

    -- Check 1: new model defaults to CANDIDATE, with no activation metadata.
    INSERT INTO public.ml_model_versions
        (id, version, bread_category_id, model_type, artifact_key, training_start, training_end)
    VALUES (candidate_model, 2, category_id, 'RANDOM_FOREST', 'rollback-only-candidate',
            DATE '2026-01-01', DATE '2026-01-31');
    IF NOT EXISTS (SELECT 1 FROM public.ml_model_versions WHERE id = candidate_model
        AND lifecycle_status = 'CANDIDATE' AND activated_by IS NULL AND activated_at IS NULL) THEN
        RAISE EXCEPTION 'FAIL 1: candidate defaults';
    END IF;

    -- Check 2: active metadata shape is accepted (not a real activation workflow).
    INSERT INTO public.ml_model_versions
        (id, version, bread_category_id, model_type, artifact_key, training_start, training_end,
         lifecycle_status, activated_by, activated_at)
    VALUES (active_model, 1, category_id, 'RANDOM_FOREST', 'rollback-only-active',
            DATE '2026-01-01', DATE '2026-01-31', 'ACTIVE', administrator_id, now());

    -- Check 3: negative R-squared and a valid nonzero MAPE are accepted.
    INSERT INTO public.model_evaluations
        (model_version_id, holdout_start, holdout_end, holdout_manifest, holdout_fingerprint,
         data_origins, evaluation_label, mae, rmse, mape, r_squared, sample_count, mape_sample_count)
    VALUES (candidate_model, DATE '2026-02-01', DATE '2026-02-10',
            '{"fixture_only":true}'::jsonb, 'rollback-only-not-a-real-digest',
            ARRAY['SIMULATION_GENERATED'], 'SIMULATION_BASED', 2, 3, 10, -0.5, 10, 8)
    RETURNING id INTO evaluation_id_value;

    -- Check 4: Second active model for same category.
    rejected := false;
    BEGIN
        UPDATE public.ml_model_versions SET lifecycle_status = 'ACTIVE', activated_by = administrator_id, activated_at = now() WHERE id = candidate_model;
    EXCEPTION WHEN unique_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Second active model for same category accepted'; END IF;

    -- Check 5: Active model without activation metadata.
    rejected := false;
    BEGIN
        UPDATE public.ml_model_versions SET activated_at = NULL WHERE id = active_model;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Active model without activation metadata accepted'; END IF;

    -- Check 6: Negative MAE.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET mae = -1 WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: Negative MAE accepted'; END IF;

    -- Check 7: RMSE below MAE.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET rmse = 1 WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: RMSE below MAE accepted'; END IF;

    -- Check 8: R-squared above one.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET r_squared = 1.1 WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: R-squared above one accepted'; END IF;

    -- Check 9: Null MAPE with nonzero MAPE count.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET mape = NULL WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Null MAPE with nonzero MAPE count accepted'; END IF;

    -- Check 10: Non-null MAPE with zero count.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET mape_sample_count = 0 WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: Non-null MAPE with zero count accepted'; END IF;

    -- Check 11: MAPE count exceeds sample count.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET mape_sample_count = 11 WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 11: MAPE count exceeds sample count accepted'; END IF;

    -- Check 12: Empty data origins.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET data_origins = ARRAY[]::text[] WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 12: Empty data origins accepted'; END IF;

    -- Check 13: Duplicate origins.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET data_origins = ARRAY['SIMULATION_GENERATED','SIMULATION_GENERATED'] WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 13: Duplicate origins accepted'; END IF;

    -- Check 14: Simulation mislabeled actual.
    rejected := false;
    BEGIN
        UPDATE public.model_evaluations SET evaluation_label = 'ACTUAL_ONLY' WHERE id = evaluation_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 14: Simulation mislabeled actual accepted'; END IF;

    -- Check 15: undefined MAPE/R-squared are stored as NULL, not perfect scores.
    UPDATE public.model_evaluations
    SET mape = NULL, mape_sample_count = 0, r_squared = NULL
    WHERE id = evaluation_id_value;
    IF NOT EXISTS (SELECT 1 FROM public.model_evaluations WHERE id = evaluation_id_value
        AND mape IS NULL AND mape_sample_count = 0 AND r_squared IS NULL) THEN
        RAISE EXCEPTION 'FAIL 15: undefined metrics not stored correctly';
    END IF;
END;
$test$;
SELECT 'PASS: all 15 model/evaluation storage checks completed' AS test_result;
ROLLBACK;
