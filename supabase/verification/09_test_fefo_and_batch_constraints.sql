-- Run the WHOLE file as postgres. All fixtures roll back.
-- Tests a reference FEFO SELECT and batch storage constraints, not an
-- implemented Repo/RPC, stock deduction, shared commitments or FIFO/FEFO costs.
BEGIN;
DO $test$
DECLARE
    ingredient_id_value uuid := gen_random_uuid();
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    c uuid := gen_random_uuid();
    d uuid := gen_random_uuid();
    expiry_day uuid := gen_random_uuid();
    selected_ids uuid[];
    rejected boolean;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    INSERT INTO public.ingredients (id, name, unit, unit_cost)
    VALUES (ingredient_id_value, 'Rollback FEFO flour ' || ingredient_id_value::text, 'KG', 4);

    INSERT INTO public.inventory_batches
        (id, ingredient_id, received_date, expiry_date,
         initial_quantity_grams, remaining_quantity_grams, unit_cost, status)
    VALUES
        (a, ingredient_id_value, DATE '2026-10-01', DATE '2026-10-30', 1000, 1000, 4, 'ACTIVE'),
        (b, ingredient_id_value, DATE '2026-10-03', DATE '2026-10-20', 1000, 1000, 5, 'ACTIVE'),
        (c, ingredient_id_value, DATE '2026-10-02', DATE '2026-10-20', 1000, 1000, 6, 'ACTIVE'),
        (d, ingredient_id_value, DATE '2026-10-03', DATE '2026-10-20', 1000, 1000, 7, 'ACTIVE'),
        (expiry_day, ingredient_id_value, DATE '2026-10-01', DATE '2026-10-10', 1000, 1000, 3, 'ACTIVE'),
        -- Expired by date even though its status has not yet been reconciled.
        (gen_random_uuid(), ingredient_id_value, DATE '2026-10-01', DATE '2026-10-09', 1000, 1000, 4, 'ACTIVE'),
        (gen_random_uuid(), ingredient_id_value, DATE '2026-10-01', DATE '2026-10-15', 1000, 1000, 4, 'DISCARDED'),
        (gen_random_uuid(), ingredient_id_value, DATE '2026-10-11', DATE '2026-10-15', 1000, 1000, 4, 'ACTIVE'),
        (gen_random_uuid(), ingredient_id_value, DATE '2026-10-01', DATE '2026-10-15', 1000, 0, 4, 'DEPLETED');

    -- Check 1: exact order and membership. Expiry date is the last usable date.
    SELECT array_agg(id ORDER BY expiry_date, received_date, id) INTO selected_ids
    FROM public.inventory_batches
    WHERE ingredient_id = ingredient_id_value
      AND status = 'ACTIVE'
      AND received_date <= DATE '2026-10-10'
      AND expiry_date >= DATE '2026-10-10'
      AND remaining_quantity_grams > 0;
    IF selected_ids IS DISTINCT FROM ARRAY[expiry_day, c, LEAST(b, d), GREATEST(b, d), a] THEN
        RAISE EXCEPTION 'FAIL 1: FEFO order/eligibility mismatch, got %', selected_ids;
    END IF;

    -- Check 2: Negative remaining quantity. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET remaining_quantity_grams = -1 WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 2: Negative remaining quantity accepted'; END IF;

    -- Check 3: Remaining exceeds initial quantity. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET remaining_quantity_grams = 1001 WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 3: Remaining exceeds initial quantity accepted'; END IF;

    -- Check 4: Active batch with zero balance. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET remaining_quantity_grams = 0 WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 4: Active batch with zero balance accepted'; END IF;

    -- Check 5: Depleted batch with positive balance. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET status = 'DEPLETED' WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 5: Depleted batch with positive balance accepted'; END IF;

    -- Check 6: Zero initial quantity. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET initial_quantity_grams = 0 WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: Zero initial quantity accepted'; END IF;

    -- Check 7: Negative batch unit cost. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET unit_cost = -1 WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: Negative batch unit cost accepted'; END IF;

    -- Check 8: Expiry equal to receipt date. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET expiry_date = received_date WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: Expiry equal to receipt date accepted'; END IF;

    -- Check 9: Unknown batch status. Change one field on valid batch A.
    rejected := false;
    BEGIN
        UPDATE public.inventory_batches SET status = 'UNKNOWN' WHERE id = a;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Unknown batch status accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 9 FEFO reference-query and batch checks completed' AS test_result;
ROLLBACK;
