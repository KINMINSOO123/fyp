-- Run the WHOLE file as postgres in Supabase SQL Editor.
-- Checks storage constraints only, not model generation, training eligibility,
-- confidence calculation, active-model validation or manager authorization.
-- No temporary tables. All fixtures roll back at the end.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    model_id uuid := gen_random_uuid();
    next_order integer;
    rejected boolean;
    failed_constraint text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Run this test using the postgres database role';
    END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order
    FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback prediction test ' || category_id::text, next_order);

    -- A candidate metadata fixture is sufficient to test the FK and null rules.
    -- This is NOT a claim that candidates are valid for operational prediction.
    INSERT INTO public.ml_model_versions
        (id, version, bread_category_id, model_type, artifact_key, training_start, training_end)
    VALUES (model_id, 1, category_id, 'RANDOM_FOREST', 'rollback-only-no-artifact',
            DATE '2026-01-01', DATE '2026-01-31');

    -- Checks 1-3: valid storage shapes, including both confidence boundaries.
    INSERT INTO public.daily_predictions
        (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
    VALUES (DATE '2026-02-01', category_id, 0, 'COLD_START', NULL, NULL),
           (DATE '2026-02-02', category_id, 10, 'MODEL', 0, model_id),
           (DATE '2026-02-03', category_id, 10, 'MODEL', 100, model_id);

    -- Check 4: Cold start with numeric confidence must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'COLD_START', 65, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Cold start with numeric confidence was accepted'; END IF;

    -- Check 5: Cold start with a model reference must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'COLD_START', NULL, model_id);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Cold start with a model reference was accepted'; END IF;

    -- Check 6: MODEL without confidence must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'MODEL', NULL, model_id);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: MODEL without confidence was accepted'; END IF;

    -- Check 7: MODEL without a model reference must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'MODEL', 75, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: MODEL without a model reference was accepted'; END IF;

    -- Check 8: Confidence below zero must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'MODEL', -1, model_id);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Confidence below zero was accepted'; END IF;

    -- Check 9: Confidence above 100 must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, 10, 'MODEL', 101, model_id);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_mode_confidence_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Confidence above 100 was accepted'; END IF;

    -- Check 10: Negative predicted quantity must be rejected by the intended constraint.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode, confidence, model_version_id)
        VALUES (DATE '2026-02-04', category_id, -1, 'COLD_START', NULL, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_predicted_units_sold_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: Negative predicted quantity was accepted'; END IF;

    -- Check 11: duplicate category/date must be rejected.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_predictions
            (target_date, bread_category_id, predicted_units_sold, prediction_mode)
        VALUES (DATE '2026-02-01', category_id, 5, 'COLD_START');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_predictions_date_category_key' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 11: duplicate category/date was accepted'; END IF;
END;
$test$;

SELECT 'PASS: all 11 prediction storage checks completed' AS test_result;
ROLLBACK;
