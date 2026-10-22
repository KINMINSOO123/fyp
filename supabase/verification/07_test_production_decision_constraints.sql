-- Run the WHOLE file as postgres. Requires an ACTIVE BAKERY_MANAGER.
-- All fixtures roll back. Tests row constraints, not authorization, shared
-- ingredient feasibility, processed-decision immutability or recommendation recalculation.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    manager_id uuid;
    prediction_id_value uuid;
    decision_id_value uuid;
    next_order integer;
    rejected boolean;
    failed_constraint text;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT user_id INTO manager_id FROM public.user_profiles
    WHERE role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' ORDER BY user_id LIMIT 1;
    IF manager_id IS NULL THEN RAISE EXCEPTION 'An ACTIVE BAKERY_MANAGER is required'; END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback decision test ' || category_id::text, next_order);
    INSERT INTO public.daily_predictions
        (target_date, bread_category_id, predicted_units_sold, prediction_mode)
    VALUES (DATE '2026-04-01', category_id, 10, 'COLD_START') RETURNING id INTO prediction_id_value;
    INSERT INTO public.production_decisions
        (target_date, bread_category_id, prediction_id, predicted_units_sold,
         recommended_production, max_producible, final_selected_qty, selected_option, confirmed_by)
    VALUES (DATE '2026-04-01', category_id, prediction_id_value, 10, 10, 15, 10,
            'ACCEPT_RECOMMENDATION', manager_id) RETURNING id INTO decision_id_value;

    -- Check 1: the accepted recommendation above is stored exactly.
    IF NOT EXISTS (SELECT 1 FROM public.production_decisions
        WHERE id = decision_id_value AND final_selected_qty = 10
          AND selected_option = 'ACCEPT_RECOMMENDATION' AND decision_reason IS NULL) THEN
        RAISE EXCEPTION 'FAIL 1: accepted recommendation not stored';
    END IF;
    -- Check 2: a reasoned reduction is valid.
    UPDATE public.production_decisions
    SET final_selected_qty = 8, selected_option = 'REDUCE', decision_reason = 'Lower planned production'
    WHERE id = decision_id_value;
    IF NOT EXISTS (SELECT 1 FROM public.production_decisions
        WHERE id = decision_id_value AND final_selected_qty = 8 AND selected_option = 'REDUCE') THEN
        RAISE EXCEPTION 'FAIL 2: reduction not stored';
    END IF;
    -- Check 3: a reasoned override within the stored limit is valid.
    UPDATE public.production_decisions
    SET final_selected_qty = 12, selected_option = 'MANUAL_OVERRIDE', decision_reason = 'Manager adjustment'
    WHERE id = decision_id_value;
    IF NOT EXISTS (SELECT 1 FROM public.production_decisions
        WHERE id = decision_id_value AND final_selected_qty = 12 AND selected_option = 'MANUAL_OVERRIDE') THEN
        RAISE EXCEPTION 'FAIL 3: override not stored';
    END IF;

    -- Check 4: Quantity above stored capacity.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET final_selected_qty = 16
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        -- PostgreSQL generated this name for the multi-column quantity CHECK.
        IF failed_constraint <> 'production_decisions_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Quantity above stored capacity accepted'; END IF;

    -- Check 5: Negative quantity.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET final_selected_qty = -1
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Negative quantity accepted'; END IF;

    -- Check 6: Override without reason.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET decision_reason = NULL
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_option_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: Override without reason accepted'; END IF;

    -- Check 7: Reduction with blank reason.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET final_selected_qty = 8, selected_option = 'REDUCE', decision_reason = '   '
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_option_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: Reduction with blank reason accepted'; END IF;

    -- Check 8: Reduction equal to recommendation.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET final_selected_qty = 10, selected_option = 'REDUCE', decision_reason = 'Reason'
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_option_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Reduction equal to recommendation accepted'; END IF;

    -- Check 9: Accept with different quantity.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET final_selected_qty = 9, selected_option = 'ACCEPT_RECOMMENDATION', decision_reason = NULL
        WHERE id = decision_id_value;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_option_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Accept with different quantity accepted'; END IF;

    -- Check 10: Decision date differs from prediction.
    rejected := false;
    BEGIN
        UPDATE public.production_decisions SET target_date = DATE '2026-04-02'
        WHERE id = decision_id_value;
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'production_decisions_prediction_context_fk' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: Decision date differs from prediction accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 10 production-decision storage checks completed' AS test_result;
ROLLBACK;
