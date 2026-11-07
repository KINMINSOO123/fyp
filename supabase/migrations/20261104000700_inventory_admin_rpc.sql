BEGIN;

-- Staged design migration. Apply after the base inventory and production tables.
-- The client only supplies business fields. Node supplies the verified actor ID.
CREATE OR REPLACE FUNCTION public.apply_inventory_admin_change_with_audit(
    p_actor_user_id uuid, p_action text, p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    changed_id uuid;
    category_id_value uuid;
    ingredient_id_value uuid;
    inventory_id_value uuid;
    receipt_day date;
    bakery_day date;
    expiry_day date;
    quantity_value numeric;
    stock_value numeric;
    old_batch public.inventory_batches%ROWTYPE;
    item jsonb;
    item_count integer;
    unique_count integer;
    operation_id_value uuid;
    event_name text;
    entity_name text;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'SYSTEM_ADMINISTRATOR'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active System Administrator is required.';
    END IF;
    IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid inventory payload.';
    END IF;

    -- This lock is also taken by manager confirmation. The later POS commit RPC
    -- must take it before batch deduction, followed by its date-specific lock.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0)
    );

    IF p_action IN ('CREATE_CATEGORY', 'UPDATE_CATEGORY') THEN
        IF (p_payload ? 'id') <> (p_action = 'UPDATE_CATEGORY') OR
           pg_catalog.jsonb_typeof(p_payload->'name') <> 'string' OR
           pg_catalog.btrim(p_payload->>'name') = '' OR
           pg_catalog.jsonb_typeof(p_payload->'displayOrder') <> 'number' OR
           pg_catalog.jsonb_typeof(p_payload->'shelfLifeHours') <> 'number' OR
           pg_catalog.jsonb_typeof(p_payload->'sellingPrice') <> 'number' OR
           pg_catalog.jsonb_typeof(p_payload->'isActive') <> 'boolean' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid category fields.';
        END IF;
        IF p_action = 'UPDATE_CATEGORY' THEN
            changed_id := (p_payload->>'id')::uuid;
            PERFORM 1 FROM public.bread_categories WHERE id = changed_id FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Category not found.';
            END IF;
            IF (p_payload->>'isActive')::boolean = false AND EXISTS (
                SELECT 1 FROM public.production_decisions AS decision
                WHERE decision.bread_category_id = changed_id
                  AND NOT EXISTS (
                      SELECT 1 FROM public.daily_production AS production
                      WHERE production.production_decision_id = decision.id
                  )
            ) THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Outstanding production decisions prevent category deactivation.';
            END IF;
            IF (p_payload->>'isActive')::boolean = true AND NOT EXISTS (
                SELECT 1 FROM public.recipes WHERE bread_category_id = changed_id
            ) THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Add a recipe before activating a category.';
            END IF;
            IF (p_payload->>'isActive')::boolean = true AND EXISTS (
                SELECT 1 FROM public.recipes AS recipe
                JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
                WHERE recipe.bread_category_id = changed_id AND NOT ingredient.is_active
            ) THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Activate recipe ingredients before the category.';
            END IF;
            UPDATE public.bread_categories SET
                name = pg_catalog.btrim(p_payload->>'name'),
                description = nullif(pg_catalog.btrim(p_payload->>'description'), ''),
                display_order = (p_payload->>'displayOrder')::integer,
                shelf_life_hours = (p_payload->>'shelfLifeHours')::integer,
                selling_price = (p_payload->>'sellingPrice')::numeric,
                is_active = (p_payload->>'isActive')::boolean
            WHERE id = changed_id;
        ELSE
            IF (p_payload->>'isActive')::boolean THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Create a category inactive, add its recipe, then activate it.';
            END IF;
            INSERT INTO public.bread_categories
                (name, description, display_order, shelf_life_hours, selling_price, is_active)
            VALUES (
                pg_catalog.btrim(p_payload->>'name'),
                nullif(pg_catalog.btrim(p_payload->>'description'), ''),
                (p_payload->>'displayOrder')::integer,
                (p_payload->>'shelfLifeHours')::integer,
                (p_payload->>'sellingPrice')::numeric,
                (p_payload->>'isActive')::boolean
            ) RETURNING id INTO changed_id;
        END IF;
        event_name := p_action;
        entity_name := 'bread_categories';

    ELSIF p_action IN ('CREATE_INGREDIENT', 'UPDATE_INGREDIENT') THEN
        IF (p_payload ? 'id') <> (p_action = 'UPDATE_INGREDIENT') OR
           pg_catalog.jsonb_typeof(p_payload->'name') <> 'string' OR
           pg_catalog.btrim(p_payload->>'name') = '' OR
           p_payload->>'unit' NOT IN ('G', 'KG') OR
           pg_catalog.jsonb_typeof(p_payload->'referenceUnitCost') <> 'number' OR
           pg_catalog.jsonb_typeof(p_payload->'reorderThresholdGrams') <> 'number' OR
           pg_catalog.jsonb_typeof(p_payload->'isActive') <> 'boolean' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid ingredient fields.';
        END IF;
        IF p_action = 'UPDATE_INGREDIENT' THEN
            changed_id := (p_payload->>'id')::uuid;
            PERFORM 1 FROM public.ingredients WHERE id = changed_id FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Ingredient not found.';
            END IF;
            IF (p_payload->>'isActive')::boolean = false AND EXISTS (
                SELECT 1 FROM public.recipes AS recipe
                JOIN public.bread_categories AS category
                  ON category.id = recipe.bread_category_id
                WHERE recipe.ingredient_id = changed_id AND category.is_active
            ) THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'An active category recipe uses this ingredient.';
            END IF;
            UPDATE public.ingredients SET
                name = pg_catalog.btrim(p_payload->>'name'),
                unit = p_payload->>'unit',
                unit_cost = (p_payload->>'referenceUnitCost')::numeric,
                reorder_threshold = (p_payload->>'reorderThresholdGrams')::numeric,
                is_active = (p_payload->>'isActive')::boolean
            WHERE id = changed_id;
        ELSE
            INSERT INTO public.ingredients
                (name, unit, unit_cost, reorder_threshold, is_active)
            VALUES (
                pg_catalog.btrim(p_payload->>'name'), p_payload->>'unit',
                (p_payload->>'referenceUnitCost')::numeric,
                (p_payload->>'reorderThresholdGrams')::numeric,
                (p_payload->>'isActive')::boolean
            ) RETURNING id INTO changed_id;
            INSERT INTO public.inventory (ingredient_id, quantity_grams, updated_by)
            VALUES (changed_id, 0, p_actor_user_id);
        END IF;
        event_name := p_action;
        entity_name := 'ingredients';

    ELSIF p_action = 'REPLACE_RECIPE' THEN
        category_id_value := (p_payload->>'breadCategoryId')::uuid;
        PERFORM 1 FROM public.bread_categories
        WHERE id = category_id_value FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Category not found.';
        END IF;
        IF pg_catalog.jsonb_typeof(p_payload->'items') <> 'array' OR
           pg_catalog.jsonb_array_length(p_payload->'items') NOT BETWEEN 1 AND 100 THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid recipe items.';
        END IF;
        SELECT pg_catalog.count(*), pg_catalog.count(DISTINCT entry.value->>'ingredientId')
          INTO item_count, unique_count
        FROM pg_catalog.jsonb_array_elements(p_payload->'items') AS entry(value);
        IF item_count <> unique_count OR EXISTS (
            SELECT 1 FROM pg_catalog.jsonb_array_elements(p_payload->'items') AS entry(value)
            WHERE pg_catalog.jsonb_typeof(entry.value->'gramsPerUnit') <> 'number'
               OR (entry.value->>'gramsPerUnit')::numeric <= 0
               OR NOT EXISTS (
                   SELECT 1 FROM public.ingredients AS ingredient
                   WHERE ingredient.id = (entry.value->>'ingredientId')::uuid
                     AND ingredient.is_active
               )
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Recipe ingredients must be unique, active and positive.';
        END IF;
        IF EXISTS (
            SELECT 1 FROM public.production_decisions AS decision
            WHERE decision.bread_category_id = category_id_value
              AND NOT EXISTS (
                  SELECT 1 FROM public.daily_production AS production
                  WHERE production.production_decision_id = decision.id
              )
        ) THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001',
                MESSAGE = 'Outstanding production decisions prevent recipe replacement.';
        END IF;
        DELETE FROM public.recipes WHERE bread_category_id = category_id_value;
        FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_payload->'items')
        LOOP
            INSERT INTO public.recipes
                (bread_category_id, ingredient_id, grams_per_unit)
            VALUES (category_id_value, (item->>'ingredientId')::uuid,
                    (item->>'gramsPerUnit')::numeric);
        END LOOP;
        changed_id := category_id_value;
        event_name := p_action;
        entity_name := 'bread_categories';

    ELSIF p_action = 'RECEIVE_BATCH' THEN
        ingredient_id_value := (p_payload->>'ingredientId')::uuid;
        SELECT id INTO inventory_id_value FROM public.inventory
        WHERE ingredient_id = ingredient_id_value FOR UPDATE;
        IF inventory_id_value IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.ingredients
            WHERE id = ingredient_id_value AND is_active
        ) THEN
            RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Active ingredient stock not found.';
        END IF;
        SELECT (pg_catalog.now() AT TIME ZONE timezone)::date
          INTO STRICT bakery_day FROM public.bakery_settings;
        receipt_day := (p_payload->>'receivedDate')::date;
        expiry_day := (p_payload->>'expiryDate')::date;
        quantity_value := (p_payload->>'quantityGrams')::numeric;
        IF receipt_day > bakery_day OR expiry_day <= bakery_day OR
           expiry_day <= receipt_day OR quantity_value <= 0 OR
           (p_payload->>'unitCostSnapshot')::numeric < 0 THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Receipt must be current, unexpired and positive.';
        END IF;
        operation_id_value := gen_random_uuid();
        INSERT INTO public.inventory_batches
            (ingredient_id, received_date, expiry_date, initial_quantity_grams,
             remaining_quantity_grams, unit_cost, source, status)
        VALUES (ingredient_id_value, receipt_day, expiry_day, quantity_value,
                quantity_value, (p_payload->>'unitCostSnapshot')::numeric,
                nullif(pg_catalog.btrim(p_payload->>'source'), ''), 'ACTIVE')
        RETURNING id INTO changed_id;
        UPDATE public.inventory SET quantity_grams = quantity_grams + quantity_value,
            updated_by = p_actor_user_id WHERE id = inventory_id_value;
        INSERT INTO public.inventory_log
            (operation_id, inventory_id, batch_id, change_grams, reason, effective_date)
        VALUES (operation_id_value, inventory_id_value, changed_id,
                quantity_value, 'RESTOCK', bakery_day);
        event_name := p_action;
        entity_name := 'inventory_batches';

    ELSIF p_action = 'REMOVE_BATCH_STOCK' THEN
        changed_id := (p_payload->>'batchId')::uuid;
        SELECT * INTO old_batch FROM public.inventory_batches
        WHERE id = changed_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Batch not found.';
        END IF;
        SELECT id, quantity_grams INTO inventory_id_value, stock_value
        FROM public.inventory WHERE ingredient_id = old_batch.ingredient_id FOR UPDATE;
        quantity_value := (p_payload->>'removedGrams')::numeric;
        IF old_batch.status <> 'ACTIVE' OR quantity_value <= 0 OR
           quantity_value > old_batch.remaining_quantity_grams OR
           quantity_value > stock_value OR
           p_payload->>'reason' NOT IN ('DISCARD', 'CORRECTION') OR
           nullif(pg_catalog.btrim(p_payload->>'note'), '') IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001',
                MESSAGE = 'Batch stock removal is invalid or exceeds available stock.';
        END IF;
        SELECT (pg_catalog.now() AT TIME ZONE timezone)::date
          INTO STRICT bakery_day FROM public.bakery_settings;
        operation_id_value := gen_random_uuid();
        UPDATE public.inventory_batches SET
            remaining_quantity_grams = remaining_quantity_grams - quantity_value,
            status = CASE WHEN remaining_quantity_grams = quantity_value
                          THEN CASE WHEN p_payload->>'reason' = 'DISCARD'
                                    THEN 'DISCARDED' ELSE 'DEPLETED' END
                          ELSE 'ACTIVE' END
        WHERE id = changed_id;
        UPDATE public.inventory SET quantity_grams = quantity_grams - quantity_value,
            updated_by = p_actor_user_id WHERE id = inventory_id_value;
        INSERT INTO public.inventory_log
            (operation_id, inventory_id, batch_id, change_grams, reason, effective_date)
        VALUES (operation_id_value, inventory_id_value, changed_id,
                -quantity_value, p_payload->>'reason', bakery_day);
        event_name := p_action;
        entity_name := 'inventory_batches';
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unknown inventory action.';
    END IF;

    INSERT INTO public.system_logs
        (actor_user_id, event_type, entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, event_name, entity_name, changed_id,
            'SUCCESS', 'INFO',
            pg_catalog.jsonb_build_object('action', p_action,
                'operation_id', operation_id_value,
                'removed_grams', CASE WHEN p_action = 'REMOVE_BATCH_STOCK'
                                      THEN quantity_value ELSE NULL END,
                'reason', CASE WHEN p_action = 'REMOVE_BATCH_STOCK'
                               THEN p_payload->>'reason' ELSE NULL END,
                'note', CASE WHEN p_action = 'REMOVE_BATCH_STOCK'
                             THEN p_payload->>'note' ELSE NULL END));
    RETURN pg_catalog.jsonb_build_object('id', changed_id, 'action', p_action);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_inventory_admin_change_with_audit(uuid, text, jsonb)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_inventory_admin_change_with_audit(uuid, text, jsonb)
    TO service_role;

COMMIT;
