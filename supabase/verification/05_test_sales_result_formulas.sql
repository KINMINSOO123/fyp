-- Run the WHOLE file as postgres in Supabase SQL Editor.
-- Requires one existing ACTIVE BAKERY_MANAGER profile.
-- All fixture rows roll back. No temporary tables or real sales are created.
-- Tests generated columns only: not POS atomicity, FEFO cost calculation,
-- source snapshot validation, sales-total reconciliation or allocation concurrency.
BEGIN;
DO $test$
DECLARE
    manager_id uuid;
    category_id uuid := gen_random_uuid();
    prediction_id_value uuid;
    decision_id_value uuid;
    production_id_value uuid;
    next_order integer;
    recommended integer;
    reason_value text;
    fixture record;
    result_row public.daily_results%ROWTYPE;
    checks integer := 0;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Run this script using the postgres database role';
    END IF;
    SELECT user_id INTO manager_id FROM public.user_profiles
    WHERE role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE'
    ORDER BY user_id LIMIT 1;
    IF manager_id IS NULL THEN
        RAISE EXCEPTION 'An ACTIVE BAKERY_MANAGER profile is required; no tests ran';
    END IF;
    SELECT COALESCE(max(display_order), -1) + 1 INTO next_order
    FROM public.bread_categories;
    INSERT INTO public.bread_categories (id, name, display_order)
    VALUES (category_id, 'Rollback results test ' || category_id::text, next_order);

    FOR fixture IN
        SELECT * FROM (VALUES
            -- name, date, predicted, produced, sold, lost, revenue, cost,
            -- expected demand, leftover, leftover percent, signed error, profit
            ('Surplus and negative profit', DATE '2026-03-01',
             90, 100, 80, 0, 160::numeric, 200::numeric, 80, 20, 20::numeric, -10, -40::numeric),
            ('Stockout: error uses sold, not demand', DATE '2026-03-02',
             100, 80, 80, 15, 160, 120, 95, 0, 0, -20, 40),
            ('Zero production: percentage unavailable', DATE '2026-03-03',
             10, 0, 0, 5, 0, 0, 5, 0, NULL, -10, 0),
            ('Sales exceed prediction: positive error', DATE '2026-03-04',
             80, 100, 90, 0, 180, 150, 90, 10, 10, 10, 30)
        ) AS cases(label, day, predicted, produced, sold, lost, revenue, cost,
                   expected_demand, expected_leftover, expected_rate, expected_error, expected_profit)
    LOOP
        prediction_id_value := gen_random_uuid();
        decision_id_value := gen_random_uuid();
        production_id_value := gen_random_uuid();
        recommended := LEAST(fixture.predicted, fixture.produced);
        reason_value := CASE WHEN fixture.produced <> recommended
            THEN 'Rollback-only manager override fixture' ELSE NULL END;

        INSERT INTO public.daily_predictions
            (id, target_date, bread_category_id, predicted_units_sold, prediction_mode)
        VALUES (prediction_id_value, fixture.day, category_id, fixture.predicted, 'COLD_START');

        INSERT INTO public.production_decisions
            (id, target_date, bread_category_id, prediction_id, predicted_units_sold,
             recommended_production, max_producible, final_selected_qty,
             selected_option, decision_reason, confirmed_by)
        VALUES (decision_id_value, fixture.day, category_id, prediction_id_value, fixture.predicted,
                recommended, fixture.produced, fixture.produced,
                CASE WHEN reason_value IS NULL THEN 'ACCEPT_RECOMMENDATION' ELSE 'MANUAL_OVERRIDE' END,
                reason_value, manager_id);

        INSERT INTO public.daily_production
            (id, production_date, bread_category_id, production_decision_id,
             recommended_qty, actual_produced, adjustment_reason)
        VALUES (production_id_value, fixture.day, category_id, decision_id_value,
                recommended, fixture.produced, reason_value);

        INSERT INTO public.daily_results
            (result_date, bread_category_id, prediction_id, daily_production_id,
             predicted_units_sold, produced, units_sold, lost_sales,
             remaining_unallocated_leftover, revenue, ingredient_cost)
        VALUES (fixture.day, category_id, prediction_id_value, production_id_value,
                fixture.predicted, fixture.produced, fixture.sold, fixture.lost,
                fixture.produced - fixture.sold, fixture.revenue, fixture.cost)
        RETURNING * INTO result_row;

        IF result_row.estimated_demand IS DISTINCT FROM fixture.expected_demand THEN
            RAISE EXCEPTION 'FAIL [%]: estimated demand, got %', fixture.label, result_row.estimated_demand;
        END IF;
        IF result_row.leftover IS DISTINCT FROM fixture.expected_leftover THEN
            RAISE EXCEPTION 'FAIL [%]: leftover, got %', fixture.label, result_row.leftover;
        END IF;
        IF result_row.leftover_rate_pct IS DISTINCT FROM fixture.expected_rate THEN
            RAISE EXCEPTION 'FAIL [%]: leftover percentage, got %', fixture.label, result_row.leftover_rate_pct;
        END IF;
        IF result_row.sales_prediction_error IS DISTINCT FROM fixture.expected_error THEN
            RAISE EXCEPTION 'FAIL [%]: signed sales error, got %', fixture.label, result_row.sales_prediction_error;
        END IF;
        IF result_row.gross_profit IS DISTINCT FROM fixture.expected_profit THEN
            RAISE EXCEPTION 'FAIL [%]: gross profit, got %', fixture.label, result_row.gross_profit;
        END IF;
        checks := checks + 5;
    END LOOP;
    IF checks <> 20 THEN RAISE EXCEPTION 'Expected 20 checks, ran %', checks; END IF;
END;
$test$;

SELECT 'PASS: all 20 sales-result formula checks completed' AS test_result;
ROLLBACK;
