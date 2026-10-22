-- Run the WHOLE file as postgres. Requires an ACTIVE BAKERY_MANAGER.
-- All fixtures roll back. Tests subtotals, a reference reporting view and
-- stored price snapshots, not export generation or automatic daily reconciliation.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    manager_id uuid;
    prediction_id_value uuid;
    decision_id_value uuid;
    production_id_value uuid;
    result_id_value uuid;
    sale_id_value uuid := gen_random_uuid();
    total_value numeric;
    group_count integer;
    next_order integer;
    rejected boolean;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT user_id INTO manager_id FROM public.user_profiles
    WHERE role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' ORDER BY user_id LIMIT 1;
    IF manager_id IS NULL THEN RAISE EXCEPTION 'An ACTIVE BAKERY_MANAGER is required'; END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback sales test ' || category_id::text, next_order);
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

    UPDATE public.daily_results SET revenue = 19 WHERE id = result_id_value;
    -- Two morning transactions must aggregate into one group (2 + 3 = 5).
    INSERT INTO public.sales_transactions
        (id, daily_result_id, sale_time, time_slot, quantity, unit_price)
    VALUES (sale_id_value, result_id_value, TIME '08:00', 'MORNING', 2, 2),
           (gen_random_uuid(), result_id_value, TIME '09:00', 'MORNING', 3, 2),
           (gen_random_uuid(), result_id_value, TIME '14:00', 'AFTERNOON', 3, 3);

    -- Check 1: generated subtotal.
    SELECT subtotal INTO total_value FROM public.sales_transactions WHERE id = sale_id_value;
    IF total_value IS DISTINCT FROM 4::numeric THEN RAISE EXCEPTION 'FAIL 1: subtotal should be 4'; END IF;
    -- Check 2: detail sum, without adding the daily total a second time.
    SELECT sum(subtotal) INTO total_value FROM public.sales_transactions WHERE daily_result_id = result_id_value;
    IF total_value IS DISTINCT FROM 19::numeric THEN RAISE EXCEPTION 'FAIL 2: subtotal sum should be 19'; END IF;
    -- Check 3: view combines morning transactions.
    SELECT total_sold INTO total_value FROM public.sales_by_timeslot
    WHERE bread_category_id = category_id AND sale_date = DATE '2026-04-01' AND time_slot = 'MORNING';
    IF total_value IS DISTINCT FROM 5::numeric THEN RAISE EXCEPTION 'FAIL 3: morning total should be 5'; END IF;
    -- Check 4: separate afternoon group.
    SELECT total_sold INTO total_value FROM public.sales_by_timeslot
    WHERE bread_category_id = category_id AND sale_date = DATE '2026-04-01' AND time_slot = 'AFTERNOON';
    IF total_value IS DISTINCT FROM 3::numeric THEN RAISE EXCEPTION 'FAIL 4: afternoon total should be 3'; END IF;
    -- Check 5: no invented empty evening group.
    SELECT count(*) INTO group_count FROM public.sales_by_timeslot WHERE bread_category_id = category_id;
    IF group_count <> 2 THEN RAISE EXCEPTION 'FAIL 5: expected exactly two groups'; END IF;
    -- Check 6: master-price changes do not rewrite transaction prices/subtotals.
    UPDATE public.bread_categories SET selling_price = 99 WHERE id = category_id;
    SELECT sum(subtotal) INTO total_value FROM public.sales_transactions WHERE daily_result_id = result_id_value;
    IF total_value IS DISTINCT FROM 19::numeric OR NOT EXISTS (
        SELECT 1 FROM public.sales_transactions WHERE id = sale_id_value AND unit_price = 2
    ) THEN RAISE EXCEPTION 'FAIL 6: historical price snapshot changed'; END IF;

    -- Check 7: Zero sale quantity.
    rejected := false;
    BEGIN
        UPDATE public.sales_transactions SET quantity = 0 WHERE id = sale_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: Zero sale quantity accepted'; END IF;

    -- Check 8: Negative sale price.
    rejected := false;
    BEGIN
        UPDATE public.sales_transactions SET unit_price = -1 WHERE id = sale_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Negative sale price accepted'; END IF;

    -- Check 9: Unknown time slot.
    rejected := false;
    BEGIN
        UPDATE public.sales_transactions SET time_slot = 'UNKNOWN' WHERE id = sale_id_value;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Unknown time slot accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 9 sales reporting/storage checks completed' AS test_result;
ROLLBACK;
