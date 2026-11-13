BEGIN;

-- Later POS method. Existing results retain the PREDICTION_SCALED_V1 label;
-- no completed simulation is recalculated or overwritten.
CREATE TABLE public.simulation_baselines (
    bread_category_id uuid PRIMARY KEY REFERENCES public.bread_categories(id)
        ON DELETE RESTRICT,
    base_demand numeric(12,3) NOT NULL CHECK (base_demand >= 0 AND base_demand <= 1000000),
    baseline_source text NOT NULL CHECK (baseline_source IN
        ('MANUAL', 'IMPORTED_HISTORICAL_AVERAGE')),
    imported_sample_count integer,
    imported_first_date date,
    imported_last_date date,
    imported_fingerprint text,
    configured_by uuid NOT NULL REFERENCES public.user_profiles(user_id)
        ON DELETE RESTRICT,
    configured_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((baseline_source = 'MANUAL' AND imported_sample_count IS NULL
        AND imported_first_date IS NULL AND imported_last_date IS NULL
        AND imported_fingerprint IS NULL) OR
      (baseline_source = 'IMPORTED_HISTORICAL_AVERAGE'
        AND imported_sample_count IS NOT NULL
        AND imported_sample_count > 0
        AND imported_first_date IS NOT NULL
        AND imported_last_date IS NOT NULL
        AND imported_first_date <= imported_last_date
        AND imported_fingerprint IS NOT NULL
        AND imported_fingerprint ~ '^[0-9a-f]{32}$'))
);
ALTER TABLE public.simulation_baselines ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.simulation_scenarios (
    singleton_guard boolean PRIMARY KEY DEFAULT true CHECK (singleton_guard),
    scenario_version integer NOT NULL CHECK (scenario_version >= 1),
    weekday_factors jsonb NOT NULL,
    weather_factors jsonb NOT NULL,
    holiday_factor numeric(8,4) NOT NULL CHECK (holiday_factor BETWEEN 0 AND 3),
    non_holiday_factor numeric(8,4) NOT NULL
        CHECK (non_holiday_factor BETWEEN 0 AND 3),
    variation_max_pct numeric(5,2) NOT NULL
        CHECK (variation_max_pct BETWEEN 0 AND 30),
    updated_by uuid REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.simulation_scenarios ENABLE ROW LEVEL SECURITY;
INSERT INTO public.simulation_scenarios(singleton_guard, scenario_version,
    weekday_factors, weather_factors, holiday_factor, non_holiday_factor,
    variation_max_pct)
VALUES (true, 1,
    '{"SUNDAY":1,"MONDAY":1,"TUESDAY":1,"WEDNESDAY":1,"THURSDAY":1,"FRIDAY":1,"SATURDAY":1}'::jsonb,
    '{"NEUTRAL":1,"CLEAR":1,"CLOUDY":1,"RAIN":1,"STORM":1,"OTHER":1}'::jsonb,
    1, 1, 10);

ALTER TABLE public.daily_results
    ADD COLUMN simulation_method text NOT NULL DEFAULT 'PREDICTION_SCALED_V1',
    ADD COLUMN simulation_snapshot jsonb,
    ADD CONSTRAINT daily_results_simulation_method_check CHECK (
      (simulation_method = 'PREDICTION_SCALED_V1' AND simulation_snapshot IS NULL) OR
      (simulation_method = 'INDEPENDENT_BASELINE_V2'
        AND simulation_snapshot IS NOT NULL
        AND jsonb_typeof(simulation_snapshot) = 'object')
    );

-- One invocation remains one atomic database transaction. Demand is computed
-- from saved scenario/baseline before the production fulfilment limit.
CREATE FUNCTION public.complete_pos_simulation_v2(
    p_actor_user_id uuid,
    p_date date,
    p_weather_condition text
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
    baseline_row public.simulation_baselines%ROWTYPE;
    scenario_row public.simulation_scenarios%ROWTYPE;
    holiday_coverage public.kl_holiday_syncs%ROWTYPE;
    weekday_key text;
    weekday_factor_value numeric;
    holiday_factor_value numeric;
    weather_factor_value numeric;
    holiday_event_ids jsonb;
    holiday_value boolean;
    seed_text text;
    variation_basis_points integer;
    variation_max_basis_points integer;
    variation_factor numeric;
    scenario_snapshot_value jsonb;
    selected_value integer;
    recommended_value integer;
    decision_reason_value text;
    ingredient_available numeric;
    needed_grams numeric;
    take_grams numeric;
    batch_cost numeric;
    category_cost numeric;
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
    IF p_weather_condition IS NULL OR p_weather_condition NOT IN
        ('NEUTRAL', 'CLEAR', 'CLOUDY', 'RAIN', 'STORM', 'OTHER') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Select a supported simulation weather scenario.';
    END IF;
    SELECT * INTO scenario_row FROM public.simulation_scenarios
      WHERE singleton_guard = true FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P1005',
            MESSAGE = 'Simulation scenario settings are missing.';
    END IF;
    PERFORM 1 FROM public.simulation_baselines AS baseline
      JOIN public.bread_categories AS category
        ON category.id = baseline.bread_category_id
      WHERE category.is_active ORDER BY baseline.bread_category_id FOR SHARE OF baseline;
    IF (SELECT count(*) FROM public.simulation_baselines AS baseline
        JOIN public.bread_categories AS category
          ON category.id = baseline.bread_category_id
        WHERE category.is_active) <> category_count THEN
        RAISE EXCEPTION USING ERRCODE = 'P1005',
            MESSAGE = 'Configure a simulation base demand for every active category.';
    END IF;
    SELECT * INTO holiday_coverage FROM public.kl_holiday_syncs
      WHERE holiday_year = EXTRACT(YEAR FROM p_date)::integer
        AND state_code = 'KUL' AND refresh_after > now() FOR SHARE;
    IF NOT FOUND OR (SELECT count(*) FROM public.calendar_events
        WHERE provider = 'MALAYSIA_HOLIDAY_API' AND state_code = 'KUL'
          AND is_current AND EXTRACT(YEAR FROM event_date)::integer =
            EXTRACT(YEAR FROM p_date)::integer) <>
          holiday_coverage.published_event_count THEN
        RAISE EXCEPTION USING ERRCODE = 'P1005',
            MESSAGE = 'Refresh complete KL public-holiday coverage before simulation.';
    END IF;
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::jsonb)
      INTO holiday_event_ids FROM public.calendar_events
      WHERE provider = 'MALAYSIA_HOLIDAY_API' AND state_code = 'KUL'
        AND is_current AND event_date = p_date;
    holiday_value := jsonb_array_length(holiday_event_ids) > 0;
    weekday_key := CASE EXTRACT(ISODOW FROM p_date)::integer
      WHEN 1 THEN 'MONDAY' WHEN 2 THEN 'TUESDAY'
      WHEN 3 THEN 'WEDNESDAY' WHEN 4 THEN 'THURSDAY'
      WHEN 5 THEN 'FRIDAY' WHEN 6 THEN 'SATURDAY'
      ELSE 'SUNDAY' END;
    weekday_factor_value := (scenario_row.weekday_factors->>weekday_key)::numeric;
    weather_factor_value :=
      (scenario_row.weather_factors->>p_weather_condition)::numeric;
    holiday_factor_value := CASE WHEN holiday_value THEN
      scenario_row.holiday_factor ELSE scenario_row.non_holiday_factor END;
    IF weekday_factor_value IS NULL OR weather_factor_value IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P1005',
            MESSAGE = 'Simulation scenario factors are incomplete.';
    END IF;
    variation_max_basis_points :=
      pg_catalog.round(scenario_row.variation_max_pct * 100)::integer;
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

        SELECT * INTO baseline_row FROM public.simulation_baselines
          WHERE bread_category_id = category_row.id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P1005',
                MESSAGE = 'Simulation base demand is missing for '
                    || category_row.name || '.';
        END IF;
        seed_text := pg_catalog.md5(p_date::text || ':' ||
          category_row.id::text || ':scenario:' ||
          scenario_row.scenario_version::text);
        variation_basis_points := (
          pg_catalog.abs(pg_catalog.hashtext(seed_text)::bigint) %
            (2 * variation_max_basis_points + 1)
          - variation_max_basis_points)::integer;
        variation_factor := 1 + variation_basis_points::numeric / 10000;
        demand_value := pg_catalog.round(baseline_row.base_demand *
          weekday_factor_value * holiday_factor_value *
          weather_factor_value * variation_factor)::integer;
        scenario_snapshot_value := pg_catalog.jsonb_build_object(
          'method', 'INDEPENDENT_BASELINE_V2',
          'baseline', pg_catalog.jsonb_build_object(
            'value', baseline_row.base_demand,
            'source', baseline_row.baseline_source,
            'configuredAt', baseline_row.configured_at,
            'importedSampleCount', baseline_row.imported_sample_count,
            'importedFirstDate', baseline_row.imported_first_date,
            'importedLastDate', baseline_row.imported_last_date,
            'importedFingerprint', baseline_row.imported_fingerprint),
          'scenarioVersion', scenario_row.scenario_version,
          'weekday', weekday_key,
          'weekdayFactor', weekday_factor_value,
          'holiday', holiday_value,
          'holidayFactor', holiday_factor_value,
          'holidayCoverageSyncedAt', holiday_coverage.last_successful_at,
          'holidayEventIds', holiday_event_ids,
          'weatherCondition', p_weather_condition,
          'weatherFactor', weather_factor_value,
          'variationMaxPct', scenario_row.variation_max_pct,
          'variationPct', variation_basis_points::numeric / 100,
          'seed', seed_text,
          'generatedDemand', demand_value);

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
            notes, simulation_method, simulation_snapshot
        ) VALUES (
            p_date, category_row.id, prediction_id_value, production_id_value,
            predicted_value, selected_value, sold_value, lost_value,
            selected_value - sold_value,
            sold_value * category_row.selling_price,
            pg_catalog.round(category_cost, 2),
            'SIMULATION_GENERATED; independent baseline scenario v2',
            'INDEPENDENT_BASELINE_V2', scenario_snapshot_value
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
            'Official atomic POS simulation v2; source is linked DailyResult'
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
        'simulatedDemand', result.estimated_demand,
        'simulationMethod', result.simulation_method,
        'simulationSnapshot', result.simulation_snapshot,
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
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_pos_simulation_v2(uuid, date, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_simulation_v2(uuid, date, text)
    TO service_role;

CREATE FUNCTION public.set_simulation_baseline(
    p_actor_user_id uuid, p_category_id uuid, p_source text,
    p_manual_base numeric DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE chosen numeric; samples integer; first_day date; last_day date;
        fingerprint text; saved public.simulation_baselines%ROWTYPE;
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
      FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'Active administrator required.'; END IF;
    PERFORM 1 FROM public.bread_categories WHERE id = p_category_id
      AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'An active bread category is required.'; END IF;
    IF p_source = 'MANUAL' THEN
      IF p_manual_base IS NULL OR p_manual_base < 0 OR
         p_manual_base > 1000000 OR p_manual_base <> round(p_manual_base, 3) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Manual base demand must be 0..1000000 with at most three decimals.';
      END IF;
      chosen := p_manual_base;
    ELSIF p_source = 'IMPORTED_HISTORICAL_AVERAGE' THEN
      IF p_manual_base IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Imported average is calculated from validated sales.';
      END IF;
      SELECT count(*), min(sales_date), max(sales_date),
        round(avg(units_sold), 3),
        pg_catalog.md5(string_agg(id::text || ':' || sales_date::text ||
          ':' || units_sold::text, '|' ORDER BY sales_date, id))
        INTO samples, first_day, last_day, chosen, fingerprint
      FROM public.daily_sales_records
      WHERE bread_category_id = p_category_id AND is_validated
        AND data_origin = 'IMPORTED_HISTORICAL'
        AND sales_date < (SELECT (now() AT TIME ZONE timezone)::date
          FROM public.bakery_settings WHERE singleton_guard = true)
        AND NOT EXISTS (SELECT 1 FROM public.daily_sales_records AS actual
          WHERE actual.bread_category_id = p_category_id
            AND actual.sales_date = daily_sales_records.sales_date
            AND actual.is_validated
            AND actual.data_origin = 'ACTUAL_TRANSACTION');
      IF samples = 0 THEN RAISE EXCEPTION USING ERRCODE = 'P1005',
        MESSAGE = 'No validated imported history is available for this category.';
      END IF;
    ELSE
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'Choose MANUAL or IMPORTED_HISTORICAL_AVERAGE.';
    END IF;
    INSERT INTO public.simulation_baselines(bread_category_id, base_demand,
      baseline_source, imported_sample_count, imported_first_date,
      imported_last_date, imported_fingerprint, configured_by, configured_at)
    VALUES (p_category_id, chosen, p_source, samples, first_day, last_day,
      fingerprint, p_actor_user_id, now())
    ON CONFLICT (bread_category_id) DO UPDATE SET
      base_demand = EXCLUDED.base_demand,
      baseline_source = EXCLUDED.baseline_source,
      imported_sample_count = EXCLUDED.imported_sample_count,
      imported_first_date = EXCLUDED.imported_first_date,
      imported_last_date = EXCLUDED.imported_last_date,
      imported_fingerprint = EXCLUDED.imported_fingerprint,
      configured_by = EXCLUDED.configured_by,
      configured_at = EXCLUDED.configured_at
    RETURNING * INTO saved;
    INSERT INTO public.system_logs(actor_user_id,event_type,entity_type,
      entity_id,outcome,severity,payload)
    VALUES (p_actor_user_id,'SIMULATION_BASELINE_SET',
      'simulation_baselines',p_category_id,'SUCCESS','INFO',
      pg_catalog.jsonb_build_object('source',p_source,'baseDemand',chosen,
        'sampleCount',samples,'fingerprint',fingerprint));
    RETURN pg_catalog.jsonb_build_object('breadCategoryId',p_category_id,
      'baseDemand',chosen,'source',p_source,'sampleCount',samples,
      'firstDate',first_day,'lastDate',last_day,
      'fingerprint',fingerprint,'configuredAt',saved.configured_at);
END; $$;
REVOKE ALL ON FUNCTION public.set_simulation_baseline(uuid,uuid,text,numeric)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_simulation_baseline(uuid,uuid,text,numeric)
  TO service_role;

CREATE FUNCTION public.update_simulation_scenario(
    p_actor_user_id uuid, p_weekday_factors jsonb,
    p_weather_factors jsonb, p_holiday_factor numeric,
    p_non_holiday_factor numeric, p_variation_max_pct numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE key_value text; saved public.simulation_scenarios%ROWTYPE;
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
      FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'Active administrator required.'; END IF;
    IF jsonb_typeof(p_weekday_factors) IS DISTINCT FROM 'object' OR
       jsonb_typeof(p_weather_factors) IS DISTINCT FROM 'object' OR
       p_holiday_factor IS NULL OR p_holiday_factor NOT BETWEEN 0 AND 3 OR
       p_non_holiday_factor IS NULL OR
       p_non_holiday_factor NOT BETWEEN 0 AND 3 OR
       p_holiday_factor <> round(p_holiday_factor, 4) OR
       p_non_holiday_factor <> round(p_non_holiday_factor, 4) OR
       p_variation_max_pct IS NULL OR
       p_variation_max_pct NOT BETWEEN 0 AND 30 OR
       p_variation_max_pct <> round(p_variation_max_pct, 2) THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'Invalid simulation scenario.';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(p_weekday_factors)) <> 7 OR
       (SELECT count(*) FROM jsonb_object_keys(p_weather_factors)) <> 6 THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'Simulation scenario factors are incomplete.';
    END IF;
    FOREACH key_value IN ARRAY ARRAY['SUNDAY','MONDAY','TUESDAY',
      'WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'] LOOP
      IF jsonb_typeof(p_weekday_factors->key_value) IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Invalid weekday simulation factor.'; END IF;
      IF (p_weekday_factors->>key_value)::numeric NOT BETWEEN 0 AND 3 OR
         (p_weekday_factors->>key_value)::numeric <>
           round((p_weekday_factors->>key_value)::numeric, 4) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Invalid weekday simulation factor.';
      END IF;
    END LOOP;
    FOREACH key_value IN ARRAY ARRAY['NEUTRAL','CLEAR','CLOUDY',
      'RAIN','STORM','OTHER'] LOOP
      IF jsonb_typeof(p_weather_factors->key_value) IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Invalid weather simulation factor.'; END IF;
      IF (p_weather_factors->>key_value)::numeric NOT BETWEEN 0 AND 3 OR
         (p_weather_factors->>key_value)::numeric <>
           round((p_weather_factors->>key_value)::numeric, 4) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
          MESSAGE = 'Invalid weather simulation factor.';
      END IF;
    END LOOP;
    UPDATE public.simulation_scenarios SET
      scenario_version = scenario_version + 1,
      weekday_factors = p_weekday_factors,
      weather_factors = p_weather_factors,
      holiday_factor = p_holiday_factor,
      non_holiday_factor = p_non_holiday_factor,
      variation_max_pct = p_variation_max_pct,
      updated_by = p_actor_user_id, updated_at = now()
    WHERE singleton_guard = true RETURNING * INTO saved;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P1005',
      MESSAGE = 'Simulation scenario setup is missing.'; END IF;
    INSERT INTO public.system_logs(actor_user_id,event_type,entity_type,
      entity_id,outcome,severity,payload)
    VALUES (p_actor_user_id,'SIMULATION_SCENARIO_UPDATED',NULL,NULL,
      'SUCCESS','INFO',pg_catalog.jsonb_build_object(
        'scenarioVersion',saved.scenario_version));
    RETURN pg_catalog.jsonb_build_object('scenarioVersion',saved.scenario_version);
END; $$;
REVOKE ALL ON FUNCTION public.update_simulation_scenario(
  uuid,jsonb,jsonb,numeric,numeric,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_simulation_scenario(
  uuid,jsonb,jsonb,numeric,numeric,numeric) TO service_role;

COMMIT;
