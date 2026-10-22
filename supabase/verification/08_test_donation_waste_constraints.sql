-- Run the WHOLE file as postgres. Requires an ACTIVE BAKERY_MANAGER.
-- All fixtures roll back. Tests storage constraints only, not allocation RPCs,
-- active-charity validation, manager authorization or concurrent over-allocation.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    manager_id uuid;
    prediction_id_value uuid;
    decision_id_value uuid;
    production_id_value uuid;
    result_id_value uuid;
    charity_id uuid := gen_random_uuid();
    donation_id_value uuid;
    waste_id_value uuid;
    next_order integer;
    rejected boolean;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT user_id INTO manager_id FROM public.user_profiles
    WHERE role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' ORDER BY user_id LIMIT 1;
    IF manager_id IS NULL THEN RAISE EXCEPTION 'An ACTIVE BAKERY_MANAGER is required'; END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback allocation test ' || category_id::text, next_order);
    INSERT INTO public.daily_predictions
        (target_date, bread_category_id, predicted_units_sold, prediction_mode)
    VALUES (DATE '2026-04-01', category_id, 10, 'COLD_START') RETURNING id INTO prediction_id_value;
    INSERT INTO public.production_decisions
        (target_date, bread_category_id, prediction_id, predicted_units_sold,
         recommended_production, max_producible, final_selected_qty, selected_option, confirmed_by)
    VALUES (DATE '2026-04-01', category_id, prediction_id_value, 10, 10, 10, 10,
            'ACCEPT_RECOMMENDATION', manager_id) RETURNING id INTO decision_id_value;
    INSERT INTO public.daily_production
        (production_date, bread_category_id, production_decision_id, recommended_qty, actual_produced)
    VALUES (DATE '2026-04-01', category_id, decision_id_value, 10, 10)
    RETURNING id INTO production_id_value;
    INSERT INTO public.daily_results
        (result_date, bread_category_id, prediction_id, daily_production_id,
         predicted_units_sold, produced, units_sold, remaining_unallocated_leftover)
    VALUES (DATE '2026-04-01', category_id, prediction_id_value, production_id_value, 10, 10, 8, 2)
    RETURNING id INTO result_id_value;

    INSERT INTO public.charity_partners (id, name)
    VALUES (charity_id, 'Rollback charity ' || charity_id::text);

    -- Check 1: valid donation defaults to PENDING.
    INSERT INTO public.donations
        (daily_result_id, charity_partner_id, donation_date, quantity, confirmed_by)
    VALUES (result_id_value, charity_id, DATE '2026-04-01', 1, manager_id)
    RETURNING id INTO donation_id_value;
    IF NOT EXISTS (SELECT 1 FROM public.donations
        WHERE id = donation_id_value AND status = 'PENDING' AND quantity = 1) THEN
        RAISE EXCEPTION 'FAIL 1: valid donation/default status';
    END IF;

    -- Check 2: valid waste with a reason is accepted.
    INSERT INTO public.waste_records
        (daily_result_id, waste_date, quantity, disposal_reason, confirmed_by)
    VALUES (result_id_value, DATE '2026-04-01', 1, 'Damaged bread', manager_id)
    RETURNING id INTO waste_id_value;
    IF NOT EXISTS (SELECT 1 FROM public.waste_records
        WHERE id = waste_id_value AND quantity = 1 AND disposal_reason = 'Damaged bread') THEN
        RAISE EXCEPTION 'FAIL 2: valid waste record';
    END IF;
    -- Maintain the fixture balance manually; no allocation service is exercised.
    UPDATE public.daily_results SET remaining_unallocated_leftover = 0 WHERE id = result_id_value;

    -- Check 3: Zero donation quantity. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.donations SET quantity = 0 WHERE id = donation_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 3: Zero donation quantity accepted'; END IF;

    -- Check 4: Negative donation quantity. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.donations SET quantity = -1 WHERE id = donation_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Negative donation quantity accepted'; END IF;

    -- Check 5: Zero waste quantity. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.waste_records SET quantity = 0 WHERE id = waste_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Zero waste quantity accepted'; END IF;

    -- Check 6: Negative waste quantity. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.waste_records SET quantity = -1 WHERE id = waste_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: Negative waste quantity accepted'; END IF;

    -- Check 7: Blank disposal reason. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.waste_records SET disposal_reason = '   ' WHERE id = waste_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: Blank disposal reason accepted'; END IF;

    -- Check 8: Missing disposal reason. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.waste_records SET disposal_reason = NULL WHERE id = waste_id_value;
    EXCEPTION WHEN not_null_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Missing disposal reason accepted'; END IF;

    -- Check 9: Unknown donation status. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.donations SET status = 'UNKNOWN' WHERE id = donation_id_value;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Unknown donation status accepted'; END IF;

    -- Check 10: Nonexistent charity reference. Change only one field on an otherwise valid row.
    rejected := false;
    BEGIN
        UPDATE public.donations SET charity_partner_id = gen_random_uuid() WHERE id = donation_id_value;
    EXCEPTION WHEN foreign_key_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: Nonexistent charity reference accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 10 donation/waste storage checks completed' AS test_result;
ROLLBACK;
