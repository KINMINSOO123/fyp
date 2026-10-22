-- Run the WHOLE file as postgres. Requires an ACTIVE BAKERY_MANAGER.
-- All fixtures roll back. Tests storage rules, not backend origin selection,
-- the 30-day threshold, equality with source units_sold or POS atomicity.
BEGIN;
DO $test$
DECLARE
    category_id uuid := gen_random_uuid();
    manager_id uuid;
    prediction_id_value uuid;
    decision_id_value uuid;
    production_id_value uuid;
    result_id_value uuid;
    source_ref text := 'rollback-' || gen_random_uuid()::text;
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
    VALUES (category_id, 'Rollback history test ' || category_id::text, next_order);
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

    -- Checks 1-3: all three valid origins can coexist for a category/day.
    INSERT INTO public.daily_sales_records
        (sales_date, bread_category_id, units_sold, data_origin, is_validated,
         source_daily_result_id, external_source_reference)
    VALUES (DATE '2026-04-01', category_id, 8, 'ACTUAL_TRANSACTION', true, NULL, source_ref || '-actual'),
           (DATE '2026-04-01', category_id, 8, 'IMPORTED_HISTORICAL', true, NULL, source_ref || '-import'),
           (DATE '2026-04-01', category_id, 8, 'SIMULATION_GENERATED', true, result_id_value, NULL);

    -- Check 4: Actual missing source.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-02', category_id, 8, 'ACTUAL_TRANSACTION', true, NULL, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Actual missing source accepted'; END IF;

    -- Check 5: Imported blank source.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-02', category_id, 8, 'IMPORTED_HISTORICAL', true, NULL, '   ');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Imported blank source accepted'; END IF;

    -- Check 6: Simulation missing result.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-02', category_id, 8, 'SIMULATION_GENERATED', true, NULL, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: Simulation missing result accepted'; END IF;

    -- Check 7: Simulation unvalidated.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-01', category_id, 8, 'SIMULATION_GENERATED', false, result_id_value, NULL);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: Simulation unvalidated accepted'; END IF;

    -- Check 8: Simulation external reference.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-01', category_id, 8, 'SIMULATION_GENERATED', true, result_id_value, 'invalid');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Simulation external reference accepted'; END IF;

    -- Check 9: Actual linked to simulation result.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-01', category_id, 8, 'ACTUAL_TRANSACTION', true, result_id_value, 'invalid');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_origin_source_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Actual linked to simulation result accepted'; END IF;

    -- Check 10: Negative sales.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-02', category_id, -1, 'IMPORTED_HISTORICAL', true, NULL, source_ref || '-negative');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_units_sold_check' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: Negative sales accepted'; END IF;

    -- Check 11: Duplicate category day origin.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-01', category_id, 8, 'ACTUAL_TRANSACTION', true, NULL, source_ref || '-duplicate');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_date_category_origin_key' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 11: Duplicate category day origin accepted'; END IF;

    -- Check 12: Reused external source on another day.
    rejected := false;
    BEGIN
        INSERT INTO public.daily_sales_records
            (sales_date, bread_category_id, units_sold, data_origin, is_validated,
             source_daily_result_id, external_source_reference)
        VALUES (DATE '2026-04-02', category_id, 8, 'IMPORTED_HISTORICAL', true, NULL, source_ref || '-import');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'idx_daily_sales_external_source' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 12: Reused external source on another day accepted'; END IF;

    -- Check 13: changing the simulation date must violate the composite FK.
    -- UPDATE avoids a duplicate-source index masking the intended FK check.
    rejected := false;
    BEGIN
        UPDATE public.daily_sales_records SET sales_date = DATE '2026-04-02'
        WHERE source_daily_result_id = result_id_value;
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'daily_sales_records_result_context_fk' THEN RAISE; END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 13: mismatched result date accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 13 sales-history storage checks completed' AS test_result;
ROLLBACK;
