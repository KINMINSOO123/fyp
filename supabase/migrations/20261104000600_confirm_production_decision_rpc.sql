BEGIN;

-- Apply only after the initial catalogue, prediction and decision migrations.
-- All confirmation writers (and the later POS commit RPC) must take this same
-- production-date advisory lock before touching date-specific stock/decisions.
CREATE OR REPLACE FUNCTION public.confirm_production_decision_with_audit(
    p_actor_user_id uuid,
    p_prediction_id uuid,
    p_final_selected_qty integer,
    p_selected_option text,
    p_decision_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_date_value date;
    category_id_value uuid;
    predicted_value integer;
    target_order integer;
    existing_id uuid;
    previous_quantity integer;
    locked_date date;
    locked_category uuid;
    locked_prediction integer;
    decision_id_value uuid;
    normalized_reason text;
    balance jsonb := '{}'::jsonb;
    ingredient_row record;
    decision_row record;
    category_row record;
    recipe_row record;
    ingredient_balance numeric;
    category_capacity numeric;
    max_after_commitments numeric := 2147483647;
    target_recommended integer;
    category_recommended integer;
    category_prediction integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.user_profiles AS actor
        WHERE actor.user_id = p_actor_user_id
          AND actor.role = 'BAKERY_MANAGER'
          AND actor.account_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;
    IF p_final_selected_qty IS NULL OR p_final_selected_qty < 0 OR
       p_selected_option IS NULL OR
       p_selected_option NOT IN
         ('ACCEPT_RECOMMENDATION', 'REDUCE', 'MANUAL_OVERRIDE') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Invalid production selection.';
    END IF;
    normalized_reason := NULLIF(btrim(p_decision_reason), '');
    IF (p_selected_option = 'ACCEPT_RECOMMENDATION' AND p_decision_reason IS NOT NULL)
       OR (p_selected_option <> 'ACCEPT_RECOMMENDATION' AND normalized_reason IS NULL) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The production option requires a valid reason.';
    END IF;

    SELECT prediction.target_date, prediction.bread_category_id,
           prediction.predicted_units_sold
      INTO target_date_value, category_id_value, predicted_value
    FROM public.daily_predictions AS prediction
    WHERE prediction.id = p_prediction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'The stored prediction was not found.';
    END IF;

    -- Catalogue/recipe/batch administrator mutations take this global lock
    -- before changing planning inputs. The later POS RPC must do the same.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0)
    );
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-production:' || target_date_value::text, 0)
    );
    -- Re-read after the lock, then lock all source rows that can change the plan.
    SELECT prediction.target_date, prediction.bread_category_id,
           prediction.predicted_units_sold
      INTO locked_date, locked_category, locked_prediction
    FROM public.daily_predictions AS prediction
    WHERE prediction.id = p_prediction_id FOR SHARE;
    IF locked_date IS DISTINCT FROM target_date_value OR
       locked_category IS DISTINCT FROM category_id_value OR
       locked_prediction IS DISTINCT FROM predicted_value THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The stored prediction changed during confirmation.';
    END IF;
    PERFORM 1 FROM public.bread_categories AS category
    WHERE category.is_active = true ORDER BY category.id FOR SHARE;
    PERFORM 1 FROM public.ingredients AS ingredient
    ORDER BY ingredient.id FOR SHARE;
    PERFORM 1 FROM public.recipes AS recipe
    ORDER BY recipe.bread_category_id, recipe.ingredient_id FOR SHARE;
    PERFORM 1 FROM public.inventory_batches AS batch
    WHERE batch.status = 'ACTIVE'
      AND batch.received_date <= target_date_value
      AND batch.expiry_date >= target_date_value
      AND batch.remaining_quantity_grams > 0
    ORDER BY batch.ingredient_id, batch.expiry_date, batch.received_date, batch.id
    FOR SHARE;
    PERFORM 1 FROM public.production_decisions AS decision
    WHERE decision.target_date = target_date_value
    ORDER BY decision.id FOR UPDATE;
    PERFORM 1 FROM public.daily_production AS production
    WHERE production.production_date = target_date_value
    ORDER BY production.id FOR SHARE;

    SELECT category.display_order INTO target_order
    FROM public.bread_categories AS category
    WHERE category.id = category_id_value AND category.is_active = true;
    IF target_order IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The predicted category is not active.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.daily_production AS production
        JOIN public.production_decisions AS decision
          ON decision.id = production.production_decision_id
        WHERE decision.prediction_id = p_prediction_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Processed production cannot be revised.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.bread_categories AS category
        WHERE category.is_active = true
          AND NOT EXISTS (
              SELECT 1 FROM public.daily_predictions AS prediction
              WHERE prediction.target_date = target_date_value
                AND prediction.bread_category_id = category.id
          )
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Stored predictions must cover every active category.';
    END IF;
    SELECT decision.id, decision.final_selected_qty
      INTO existing_id, previous_quantity
    FROM public.production_decisions AS decision
    WHERE decision.prediction_id = p_prediction_id;

    FOR ingredient_row IN
        SELECT ingredient.id, ingredient.name,
               COALESCE(sum(batch.remaining_quantity_grams), 0)::numeric AS available
        FROM public.ingredients AS ingredient
        LEFT JOIN public.inventory_batches AS batch
          ON batch.ingredient_id = ingredient.id
         AND batch.status = 'ACTIVE'
         AND batch.received_date <= target_date_value
         AND batch.expiry_date >= target_date_value
         AND batch.remaining_quantity_grams > 0
        GROUP BY ingredient.id, ingredient.name
        ORDER BY ingredient.id
    LOOP
        balance := pg_catalog.jsonb_set(balance,
            ARRAY[ingredient_row.id::text], pg_catalog.to_jsonb(ingredient_row.available));
    END LOOP;

    -- Reserve every other confirmed but unprocessed quantity. The old version
    -- of this prediction is excluded, so revision replaces rather than adds.
    FOR decision_row IN
        SELECT decision.id, decision.bread_category_id,
               decision.final_selected_qty
        FROM public.production_decisions AS decision
        WHERE decision.target_date = target_date_value
          AND decision.prediction_id <> p_prediction_id
          AND NOT EXISTS (
              SELECT 1 FROM public.daily_production AS production
              WHERE production.production_decision_id = decision.id
          )
        ORDER BY decision.bread_category_id, decision.id
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            WHERE recipe.bread_category_id = decision_row.bread_category_id
        ) OR EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
            WHERE recipe.bread_category_id = decision_row.bread_category_id
              AND ingredient.is_active = false
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'An outstanding decision has no recipe.';
        END IF;
        FOR recipe_row IN
            SELECT recipe.ingredient_id, recipe.grams_per_unit
            FROM public.recipes AS recipe
            JOIN public.ingredients AS ingredient
              ON ingredient.id = recipe.ingredient_id
            WHERE recipe.bread_category_id = decision_row.bread_category_id
              AND ingredient.is_active = true
            ORDER BY recipe.ingredient_id
        LOOP
            ingredient_balance := COALESCE(
                (balance->>recipe_row.ingredient_id::text)::numeric, 0);
            balance := pg_catalog.jsonb_set(balance,
                ARRAY[recipe_row.ingredient_id::text],
                pg_catalog.to_jsonb(ingredient_balance -
                    recipe_row.grams_per_unit * decision_row.final_selected_qty));
        END LOOP;
    END LOOP;

    FOR ingredient_row IN
        SELECT ingredient.id, ingredient.name
        FROM public.ingredients AS ingredient ORDER BY ingredient.id
    LOOP
        ingredient_balance := COALESCE((balance->>ingredient_row.id::text)::numeric, 0);
        IF ingredient_balance < 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001',
                MESSAGE = 'Existing commitments exceed valid ' || ingredient_row.name || ' stock.';
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM public.recipes AS recipe
        WHERE recipe.bread_category_id = category_id_value
    ) OR EXISTS (
        SELECT 1 FROM public.recipes AS recipe
        JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
        WHERE recipe.bread_category_id = category_id_value
          AND ingredient.is_active = false
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The selected category needs a valid active recipe.';
    END IF;
    FOR recipe_row IN
        SELECT recipe.ingredient_id, recipe.grams_per_unit
        FROM public.recipes AS recipe
        WHERE recipe.bread_category_id = category_id_value
        ORDER BY recipe.ingredient_id
    LOOP
        max_after_commitments := LEAST(max_after_commitments,
            floor(COALESCE((balance->>recipe_row.ingredient_id::text)::numeric, 0)
                / recipe_row.grams_per_unit));
    END LOOP;
    IF p_final_selected_qty > max_after_commitments THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'Selected production exceeds jointly available ingredients.';
    END IF;

    -- Allocate earlier unconfirmed categories in display order to recover the
    -- selected category's current recommendation under the same row locks.
    FOR category_row IN
        SELECT category.id, category.display_order
        FROM public.bread_categories AS category
        WHERE category.is_active = true
          AND category.display_order <= target_order
        ORDER BY category.display_order, category.id
    LOOP
        IF category_row.id <> category_id_value AND EXISTS (
            SELECT 1 FROM public.production_decisions AS decision
            WHERE decision.target_date = target_date_value
              AND decision.bread_category_id = category_row.id
        ) THEN
            -- Outstanding decisions have already been reserved. Processed
            -- decisions have already consumed their stock and are skipped.
            CONTINUE;
        END IF;
        SELECT prediction.predicted_units_sold INTO category_prediction
        FROM public.daily_predictions AS prediction
        WHERE prediction.target_date = target_date_value
          AND prediction.bread_category_id = category_row.id;
        category_capacity := 2147483647;
        IF NOT EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            WHERE recipe.bread_category_id = category_row.id
        ) OR EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
            WHERE recipe.bread_category_id = category_row.id
              AND ingredient.is_active = false
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'An earlier category has an invalid recipe.';
        END IF;
        FOR recipe_row IN
            SELECT recipe.ingredient_id, recipe.grams_per_unit
            FROM public.recipes AS recipe
            WHERE recipe.bread_category_id = category_row.id
            ORDER BY recipe.ingredient_id
        LOOP
            category_capacity := LEAST(category_capacity,
                floor(GREATEST(0, COALESCE(
                    (balance->>recipe_row.ingredient_id::text)::numeric, 0))
                    / recipe_row.grams_per_unit));
        END LOOP;
        category_recommended := LEAST(category_prediction, category_capacity)::integer;
        IF category_row.id = category_id_value THEN
            target_recommended := category_recommended;
            EXIT;
        END IF;
        FOR recipe_row IN
            SELECT recipe.ingredient_id, recipe.grams_per_unit
            FROM public.recipes AS recipe
            WHERE recipe.bread_category_id = category_row.id
            ORDER BY recipe.ingredient_id
        LOOP
            ingredient_balance := COALESCE(
                (balance->>recipe_row.ingredient_id::text)::numeric, 0);
            balance := pg_catalog.jsonb_set(balance,
                ARRAY[recipe_row.ingredient_id::text],
                pg_catalog.to_jsonb(ingredient_balance -
                    recipe_row.grams_per_unit * category_recommended));
        END LOOP;
    END LOOP;
    IF target_recommended IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Unable to determine the current recommendation.';
    END IF;
    IF (p_selected_option = 'ACCEPT_RECOMMENDATION'
          AND p_final_selected_qty <> target_recommended)
       OR (p_selected_option = 'REDUCE'
          AND p_final_selected_qty >= target_recommended) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The selected option does not match the current recommendation.';
    END IF;

    INSERT INTO public.production_decisions (
        target_date, bread_category_id, prediction_id,
        predicted_units_sold, recommended_production, max_producible,
        final_selected_qty, selected_option, decision_reason,
        confirmed_by, confirmed_at
    ) VALUES (
        target_date_value, category_id_value, p_prediction_id,
        predicted_value, target_recommended, max_after_commitments::integer,
        p_final_selected_qty, p_selected_option, normalized_reason,
        p_actor_user_id, now()
    )
    ON CONFLICT (prediction_id) DO UPDATE SET
        predicted_units_sold = EXCLUDED.predicted_units_sold,
        recommended_production = EXCLUDED.recommended_production,
        max_producible = EXCLUDED.max_producible,
        final_selected_qty = EXCLUDED.final_selected_qty,
        selected_option = EXCLUDED.selected_option,
        decision_reason = EXCLUDED.decision_reason,
        confirmed_by = EXCLUDED.confirmed_by,
        confirmed_at = EXCLUDED.confirmed_at
    RETURNING id INTO decision_id_value;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id,
        CASE WHEN existing_id IS NULL THEN 'PRODUCTION_CONFIRMED'
             ELSE 'PRODUCTION_REVISED' END,
        'production_decisions', decision_id_value,
        'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object(
            'target_date', target_date_value,
            'bread_category_id', category_id_value,
            'prediction_id', p_prediction_id,
            'previous_quantity', previous_quantity,
            'selected_quantity', p_final_selected_qty,
            'recommended_quantity', target_recommended
        )
    );
    RETURN decision_id_value;
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_production_decision_with_audit(
    uuid, uuid, integer, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_production_decision_with_audit(
    uuid, uuid, integer, text, text
) TO service_role;

COMMIT;
