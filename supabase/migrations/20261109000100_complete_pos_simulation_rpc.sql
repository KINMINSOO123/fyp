BEGIN;

-- Staged POS commit boundary. Apply after the base POS tables and the production
-- confirmation and inventory administration RPCs. One invocation is one database
-- transaction: any exception rolls back every category and every write.
CREATE FUNCTION public.complete_pos_simulation(
    p_actor_user_id uuid,
    p_date date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    bakery_day date;
    bakery_open time;
    bakery_close time;
    operation_id_value uuid := pg_catalog.gen_random_uuid();
    category_row record;
    ingredient_row record;
    recipe_row record;
    batch_row record;
    prediction_id_value uuid;
    decision_id_value uuid;
    production_id_value uuid;
    result_id_value uuid;
    inventory_id_value uuid;
    predicted_value integer;
    selected_value integer;
    recommended_value integer;
    decision_reason_value text;
    ingredient_available numeric;
    needed_grams numeric;
    take_grams numeric;
    batch_cost numeric;
    category_cost numeric;
    variation_pct integer;
    morning_weight integer;
    afternoon_weight integer;
    demand_value integer;
    sold_value integer;
    lost_value integer;
    morning_value integer;
    afternoon_value integer;
    evening_value integer;
    category_count integer := 0;
    result_items jsonb;
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'A simulation date is required.';
    END IF;
    PERFORM 1 FROM public.user_profiles AS actor
    WHERE actor.user_id = p_actor_user_id
      AND actor.role = 'BAKERY_MANAGER'
      AND actor.account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;

    -- Same lock order as confirmation and catalogue/batch administration.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-production:' || p_date::text, 0));
    -- Recheck identity after waiting for locks; an administrator may have
    -- disabled the account while the request was queued.
    PERFORM 1 FROM public.user_profiles AS actor
    WHERE actor.user_id = p_actor_user_id
      AND actor.role = 'BAKERY_MANAGER'
      AND actor.account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;

    SELECT settings.opens_at, settings.closes_at,
           (now() AT TIME ZONE settings.timezone)::date
      INTO bakery_open, bakery_close, bakery_day
    FROM public.bakery_settings AS settings
    WHERE settings.singleton_guard = true FOR SHARE;
    IF NOT FOUND OR bakery_open >= bakery_close THEN
        RAISE EXCEPTION USING ERRCODE = 'P1004',
            MESSAGE = 'Bakery hours or timezone are unavailable.';
    END IF;
    IF p_date > bakery_day THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Official simulation cannot run for a future date.';
    END IF;

    PERFORM 1 FROM public.bread_categories AS category
      WHERE category.is_active ORDER BY category.id FOR SHARE;
    PERFORM 1 FROM public.ingredients AS ingredient
      ORDER BY ingredient.id FOR SHARE;
    PERFORM 1 FROM public.recipes AS recipe
      ORDER BY recipe.bread_category_id, recipe.ingredient_id FOR SHARE;
    PERFORM 1 FROM public.inventory AS snapshot
      ORDER BY snapshot.ingredient_id FOR UPDATE;
    PERFORM 1 FROM public.inventory_batches AS batch
      WHERE batch.status = 'ACTIVE' AND batch.received_date <= p_date
        AND batch.expiry_date >= p_date AND batch.remaining_quantity_grams > 0
      ORDER BY batch.ingredient_id, batch.expiry_date,
               batch.received_date, batch.id FOR UPDATE;
    PERFORM 1 FROM public.daily_predictions AS prediction
      WHERE prediction.target_date = p_date ORDER BY prediction.id FOR SHARE;
    PERFORM 1 FROM public.production_decisions AS decision
      WHERE decision.target_date = p_date ORDER BY decision.id FOR UPDATE;

    IF EXISTS (SELECT 1 FROM public.daily_production
               WHERE production_date = p_date)
       OR EXISTS (SELECT 1 FROM public.daily_results
                  WHERE result_date = p_date) THEN
        RAISE EXCEPTION USING ERRCODE = 'P1001',
            MESSAGE = 'This date already has completed production or results.';
    END IF;
    SELECT count(*) INTO category_count FROM public.bread_categories
    WHERE is_active = true;
    IF category_count = 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'P1004',
            MESSAGE = 'There are no active bread categories.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.production_decisions AS decision
        JOIN public.bread_categories AS category
          ON category.id = decision.bread_category_id
        WHERE decision.target_date = p_date AND NOT category.is_active
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P1002',
            MESSAGE = 'An inactive category has an outstanding decision.';
    END IF;

    -- Check complete prediction/confirmation/recipe coverage before changing
    -- any inventory. All active categories form one all-or-nothing operation.
    FOR category_row IN
        SELECT id, name FROM public.bread_categories
        WHERE is_active ORDER BY display_order, id
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.daily_predictions AS prediction
            JOIN public.production_decisions AS decision
              ON decision.prediction_id = prediction.id
             AND decision.target_date = prediction.target_date
             AND decision.bread_category_id = prediction.bread_category_id
            WHERE prediction.target_date = p_date
              AND prediction.bread_category_id = category_row.id
        ) THEN
            RAISE EXCEPTION USING ERRCODE = 'P1002',
                MESSAGE = 'Stored prediction and manager confirmation required for '
                    || category_row.name || '.';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            WHERE recipe.bread_category_id = category_row.id
        ) OR EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            JOIN public.ingredients AS ingredient
              ON ingredient.id = recipe.ingredient_id
            WHERE recipe.bread_category_id = category_row.id
              AND NOT ingredient.is_active
        ) THEN
            RAISE EXCEPTION USING ERRCODE = 'P1004',
                MESSAGE = 'An active category has no valid active recipe.';
        END IF;
    END LOOP;

    -- Shared-ingredient requirement covers every unprocessed confirmation,
    -- including manager overrides. The batch filter is the production-date
    -- validity rule; the inventory snapshot may include expired stock.
    FOR ingredient_row IN
        SELECT recipe.ingredient_id,
               sum(recipe.grams_per_unit * decision.final_selected_qty) AS required
        FROM public.production_decisions AS decision
        JOIN public.recipes AS recipe
          ON recipe.bread_category_id = decision.bread_category_id
        WHERE decision.target_date = p_date
        GROUP BY recipe.ingredient_id ORDER BY recipe.ingredient_id
    LOOP
        SELECT COALESCE(sum(batch.remaining_quantity_grams), 0)
          INTO ingredient_available
        FROM public.inventory_batches AS batch
        WHERE batch.ingredient_id = ingredient_row.ingredient_id
          AND batch.status = 'ACTIVE'
          AND batch.received_date <= p_date AND batch.expiry_date >= p_date
          AND batch.remaining_quantity_grams > 0;
        IF ingredient_row.required > ingredient_available THEN
            RAISE EXCEPTION USING ERRCODE = 'P1003',
                MESSAGE = 'Confirmed production exceeds valid shared ingredient stock.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.inventory
                       WHERE ingredient_id = ingredient_row.ingredient_id) THEN
            RAISE EXCEPTION USING ERRCODE = 'P1004',
                MESSAGE = 'An ingredient inventory snapshot is missing.';
        END IF;
    END LOOP;

    FOR category_row IN
        SELECT id, name, selling_price FROM public.bread_categories
        WHERE is_active ORDER BY display_order, id
    LOOP
        SELECT prediction.id, prediction.predicted_units_sold,
               decision.id, decision.final_selected_qty,
               decision.recommended_production, decision.decision_reason
          INTO prediction_id_value, predicted_value, decision_id_value,
               selected_value, recommended_value, decision_reason_value
        FROM public.daily_predictions AS prediction
        JOIN public.production_decisions AS decision
          ON decision.prediction_id = prediction.id
        WHERE prediction.target_date = p_date
          AND prediction.bread_category_id = category_row.id;

        category_cost := 0;
        FOR recipe_row IN
            SELECT ingredient_id, grams_per_unit FROM public.recipes
            WHERE bread_category_id = category_row.id ORDER BY ingredient_id
        LOOP
            needed_grams := recipe_row.grams_per_unit * selected_value;
            IF needed_grams = 0 THEN CONTINUE; END IF;
            SELECT id INTO inventory_id_value FROM public.inventory
            WHERE ingredient_id = recipe_row.ingredient_id;
            FOR batch_row IN
                SELECT id, remaining_quantity_grams, unit_cost
                FROM public.inventory_batches
                WHERE ingredient_id = recipe_row.ingredient_id
                  AND status = 'ACTIVE' AND received_date <= p_date
                  AND expiry_date >= p_date AND remaining_quantity_grams > 0
                ORDER BY expiry_date, received_date, id FOR UPDATE
            LOOP
                EXIT WHEN needed_grams = 0;
                take_grams := LEAST(needed_grams, batch_row.remaining_quantity_grams);
                batch_cost := take_grams / 1000 * batch_row.unit_cost;
                UPDATE public.inventory_batches SET
                    remaining_quantity_grams = remaining_quantity_grams - take_grams,
                    status = CASE WHEN remaining_quantity_grams = take_grams
                                  THEN 'DEPLETED' ELSE 'ACTIVE' END
                WHERE id = batch_row.id;
                UPDATE public.inventory SET
                    quantity_grams = quantity_grams - take_grams,
                    updated_by = p_actor_user_id
                WHERE id = inventory_id_value AND quantity_grams >= take_grams;
                IF NOT FOUND THEN
                    RAISE EXCEPTION USING ERRCODE = 'P1004',
                        MESSAGE = 'Inventory snapshot disagrees with its batches.';
                END IF;
                INSERT INTO public.inventory_log (
                    operation_id, inventory_id, batch_id,
                    production_decision_id, change_grams, reason, effective_date
                ) VALUES (
                    operation_id_value, inventory_id_value, batch_row.id,
                    decision_id_value, -take_grams, 'PRODUCTION_DEDUCTION', p_date
                );
                category_cost := category_cost + batch_cost;
                needed_grams := needed_grams - take_grams;
            END LOOP;
            IF needed_grams <> 0 THEN
                RAISE EXCEPTION USING ERRCODE = 'P1003',
                    MESSAGE = 'Valid ingredient batches became insufficient.';
            END IF;
        END LOOP;

        INSERT INTO public.daily_production (
            production_date, bread_category_id, production_decision_id,
            recommended_qty, actual_produced, adjustment_reason
        ) VALUES (
            p_date, category_row.id, decision_id_value,
            recommended_value, selected_value,
            CASE WHEN selected_value = recommended_value THEN NULL
                 ELSE decision_reason_value END
        ) RETURNING id INTO production_id_value;

        -- The prediction already includes calendar/weather/season context.
        -- Stable 90..110% variation represents daily simulated demand only.
        variation_pct := 90 + (
            pg_catalog.abs(pg_catalog.hashtext(p_date::text || ':' ||
                category_row.id::text)::bigint) % 21)::integer;
        demand_value := LEAST(2147483647::numeric,
            pg_catalog.round(predicted_value::numeric * variation_pct / 100))::integer;
        sold_value := LEAST(demand_value, selected_value);
        lost_value := GREATEST(0, demand_value - selected_value);
        morning_weight := 30 + (
            pg_catalog.abs(pg_catalog.hashtext(p_date::text || ':' ||
                category_row.id::text || ':morning')::bigint) % 16)::integer;
        afternoon_weight := 30 + (
            pg_catalog.abs(pg_catalog.hashtext(p_date::text || ':' ||
                category_row.id::text || ':afternoon')::bigint) % 16)::integer;
        morning_value := pg_catalog.floor(
            sold_value::numeric * morning_weight / 100)::integer;
        afternoon_value := pg_catalog.floor(
            sold_value::numeric * afternoon_weight / 100)::integer;
        evening_value := sold_value - morning_value - afternoon_value;

        INSERT INTO public.daily_results (
            result_date, bread_category_id, prediction_id, daily_production_id,
            predicted_units_sold, produced, units_sold, lost_sales,
            remaining_unallocated_leftover, revenue, ingredient_cost,
            notes
        ) VALUES (
            p_date, category_row.id, prediction_id_value, production_id_value,
            predicted_value, selected_value, sold_value, lost_value,
            selected_value - sold_value,
            sold_value * category_row.selling_price,
            pg_catalog.round(category_cost, 2),
            'SIMULATION_GENERATED; deterministic date/category demand and slot variation'
        ) RETURNING id INTO result_id_value;

        IF morning_value > 0 THEN
            INSERT INTO public.sales_transactions (
                daily_result_id, sale_time, time_slot, quantity, unit_price
            ) VALUES (
                result_id_value,
                bakery_open + (bakery_close - bakery_open) / 6,
                'MORNING', morning_value, category_row.selling_price
            );
        END IF;
        IF afternoon_value > 0 THEN
            INSERT INTO public.sales_transactions (
                daily_result_id, sale_time, time_slot, quantity, unit_price
            ) VALUES (
                result_id_value,
                bakery_open + (bakery_close - bakery_open) / 2,
                'AFTERNOON', afternoon_value, category_row.selling_price
            );
        END IF;
        IF evening_value > 0 THEN
            INSERT INTO public.sales_transactions (
                daily_result_id, sale_time, time_slot, quantity, unit_price
            ) VALUES (
                result_id_value,
                bakery_open + (bakery_close - bakery_open) * 5 / 6,
                'EVENING', evening_value, category_row.selling_price
            );
        END IF;

        INSERT INTO public.daily_sales_records (
            sales_date, bread_category_id, units_sold, data_origin,
            is_validated, source_daily_result_id, external_source_reference,
            validation_notes
        ) VALUES (
            p_date, category_row.id, sold_value, 'SIMULATION_GENERATED',
            true, result_id_value, NULL,
            'Official atomic POS simulation; source is linked DailyResult'
        );
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM public.daily_results AS result
        WHERE result.result_date = p_date AND (
          (SELECT COALESCE(sum(sale.quantity), 0)
           FROM public.sales_transactions AS sale
           WHERE sale.daily_result_id = result.id) <> result.units_sold
          OR (SELECT COALESCE(sum(sale.subtotal), 0)
              FROM public.sales_transactions AS sale
              WHERE sale.daily_result_id = result.id) <> result.revenue
        )
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P1004',
            MESSAGE = 'Simulation transaction totals do not reconcile.';
    END IF;
    INSERT INTO public.system_logs (
        actor_user_id, event_type, outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'SIMULATION_COMPLETED', 'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object('date', p_date,
            'operation_id', operation_id_value, 'category_count', category_count)
    );
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'breadCategoryId', result.bread_category_id,
        'breadCategoryName', category.name,
        'predictionId', result.prediction_id,
        'productionDecisionId', production.production_decision_id,
        'dailyProductionId', production.id,
        'dailyResultId', result.id,
        'predictedUnitsSold', result.predicted_units_sold,
        'predictionMode', prediction.prediction_mode,
        'confidence', prediction.confidence,
        'modelVersionId', prediction.model_version_id,
        'produced', result.produced, 'unitsSold', result.units_sold,
        'lostSales', result.lost_sales, 'estimatedDemand', result.estimated_demand,
        'leftover', result.leftover,
        'remainingUnallocatedLeftover', result.remaining_unallocated_leftover,
        'salesPredictionError', result.sales_prediction_error,
        'leftoverRatePct', result.leftover_rate_pct,
        'revenue', result.revenue, 'ingredientCost', result.ingredient_cost,
        'grossProfit', result.gross_profit,
        'dataOrigin', 'SIMULATION_GENERATED'
    ) ORDER BY category.display_order), '[]'::jsonb) INTO result_items
    FROM public.daily_results AS result
    JOIN public.daily_production AS production
      ON production.id = result.daily_production_id
    JOIN public.daily_predictions AS prediction
      ON prediction.id = result.prediction_id
    JOIN public.bread_categories AS category
      ON category.id = result.bread_category_id
    WHERE result.result_date = p_date;
    RETURN pg_catalog.jsonb_build_object(
        'date', p_date, 'operationId', operation_id_value,
        'items', result_items);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_pos_simulation(uuid, date)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_simulation(uuid, date)
    TO service_role;

COMMIT;
