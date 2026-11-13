BEGIN;
ALTER TABLE public.inventory_batches
    ADD COLUMN direct_receipt_key uuid UNIQUE;
COMMIT;
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
    WHERE user_id = p_actor_user_id AND role = CASE WHEN p_action IN ('RECEIVE_BATCH', 'REMOVE_BATCH_STOCK') THEN 'BAKERY_MANAGER' ELSE 'SYSTEM_ADMINISTRATOR' END
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'The active role required for this inventory action is missing.';
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
        IF pg_catalog.jsonb_typeof(p_payload->'receiptKey') <> 'string' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Receipt key required.';
        END IF;
        SELECT * INTO old_batch FROM public.inventory_batches
        WHERE direct_receipt_key = (p_payload->>'receiptKey')::uuid FOR UPDATE;
        IF FOUND THEN
            IF old_batch.ingredient_id <> (p_payload->>'ingredientId')::uuid OR
               old_batch.initial_quantity_grams <> (p_payload->>'quantityGrams')::numeric OR
               old_batch.received_date <> (p_payload->>'receivedDate')::date OR
               old_batch.expiry_date <> (p_payload->>'expiryDate')::date OR
               old_batch.unit_cost <> (p_payload->>'unitCostSnapshot')::numeric OR
               old_batch.source IS DISTINCT FROM
                 nullif(pg_catalog.btrim(p_payload->>'source'), '') THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Receipt key reused with different data.';
            END IF;
            RETURN pg_catalog.jsonb_build_object('id', old_batch.id,
                'action', p_action, 'alreadyRecorded', true);
        END IF;
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
             remaining_quantity_grams, unit_cost, source, status, direct_receipt_key)
        VALUES (ingredient_id_value, receipt_day, expiry_day, quantity_value,
                quantity_value, (p_payload->>'unitCostSnapshot')::numeric,
                nullif(pg_catalog.btrim(p_payload->>'source'), ''), 'ACTIVE', (p_payload->>'receiptKey')::uuid)
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

BEGIN;
CREATE OR REPLACE FUNCTION public.receive_restock_batch(
    p_actor_user_id uuid, p_item_id uuid, p_receipt_key uuid, p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restock_requests%ROWTYPE;
    item_row public.restock_request_items%ROWTYPE;
    existing_batch public.inventory_batches%ROWTYPE;
    batch_result jsonb; batch_id_value uuid; request_id_value uuid;
    received numeric; outstanding numeric; remaining_items integer;
BEGIN
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active bakery manager required.';
    END IF;
    IF p_item_id IS NULL OR p_receipt_key IS NULL OR p_payload IS NULL
       OR jsonb_typeof(p_payload) <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid linked receipt.';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    SELECT * INTO existing_batch FROM public.inventory_batches
    WHERE restock_receipt_key = p_receipt_key;
    IF FOUND THEN
        IF existing_batch.restock_request_item_id <> p_item_id OR
           existing_batch.ingredient_id <> (p_payload->>'ingredientId')::uuid OR
           existing_batch.initial_quantity_grams <> (p_payload->>'quantityGrams')::numeric OR
           existing_batch.received_date <> (p_payload->>'receivedDate')::date OR
           existing_batch.expiry_date <> (p_payload->>'expiryDate')::date OR
           existing_batch.unit_cost <> (p_payload->>'unitCostSnapshot')::numeric OR
           existing_batch.source IS DISTINCT FROM nullif(btrim(p_payload->>'source'), '') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Receipt key reused with different data.';
        END IF;
        SELECT request_id INTO request_id_value
        FROM public.restock_request_items
        WHERE id = existing_batch.restock_request_item_id;
        RETURN jsonb_build_object('id', existing_batch.id,
            'restockRequestId', request_id_value, 'alreadyRecorded', true);
    END IF;
    SELECT request_id INTO request_id_value FROM public.restock_request_items
    WHERE id = p_item_id;
    IF request_id_value IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Restock item not found.';
    END IF;
    SELECT * INTO request_row FROM public.restock_requests
    WHERE id = request_id_value FOR UPDATE;
    SELECT * INTO item_row FROM public.restock_request_items
    WHERE id = p_item_id FOR UPDATE;
    IF request_row.status NOT IN ('PENDING', 'PARTIALLY_RECEIVED') OR
       item_row.ingredient_id <> (p_payload->>'ingredientId')::uuid THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Restock item is not open for this ingredient.';
    END IF;
    SELECT coalesce(sum(initial_quantity_grams), 0) INTO received
    FROM public.inventory_batches WHERE restock_request_item_id = p_item_id;
    outstanding := item_row.requested_grams - item_row.cancelled_grams - received;
    IF (p_payload->>'quantityGrams')::numeric <= 0 OR
       (p_payload->>'quantityGrams')::numeric > outstanding THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Receipt exceeds outstanding restock quantity.';
    END IF;
    batch_result := public.apply_inventory_admin_change_with_audit(
        p_actor_user_id, 'RECEIVE_BATCH', p_payload || pg_catalog.jsonb_build_object('receiptKey', p_receipt_key));
    batch_id_value := (batch_result->>'id')::uuid;
    UPDATE public.inventory_batches SET restock_request_item_id = p_item_id,
        restock_receipt_key = p_receipt_key WHERE id = batch_id_value;
    SELECT count(*) INTO remaining_items FROM public.restock_request_items AS item
    WHERE item.request_id = request_row.id AND item.requested_grams >
        item.cancelled_grams + coalesce((
            SELECT sum(batch.initial_quantity_grams)
            FROM public.inventory_batches AS batch
            WHERE batch.restock_request_item_id = item.id), 0);
    UPDATE public.restock_requests SET
        status = CASE WHEN remaining_items = 0 THEN 'FULFILLED'
                      ELSE 'PARTIALLY_RECEIVED' END,
        updated_at = now(),
        closed_at = CASE WHEN remaining_items = 0 THEN now() ELSE NULL END
    WHERE id = request_row.id;
    INSERT INTO public.system_logs
        (actor_user_id, event_type, entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, 'RESTOCK_BATCH_RECEIVED',
        'restock_requests', request_row.id, 'SUCCESS', 'INFO',
        jsonb_build_object('batchId', batch_id_value, 'itemId', p_item_id,
            'quantityGrams', p_payload->'quantityGrams'));
    RETURN jsonb_build_object('id', batch_id_value,
        'restockRequestId', request_row.id, 'alreadyRecorded', false);
END;
$$;
CREATE OR REPLACE FUNCTION public.cancel_restock_outstanding(
    p_actor_user_id uuid, p_request_id uuid, p_reason text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restock_requests%ROWTYPE; receipt_count integer;
BEGIN
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active bakery manager required.';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Cancellation reason required.';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    SELECT * INTO request_row FROM public.restock_requests
    WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Restock request not found.';
    END IF;
    IF request_row.status NOT IN ('PENDING', 'PARTIALLY_RECEIVED') THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'No outstanding quantity remains.';
    END IF;
    UPDATE public.restock_request_items AS item SET cancelled_grams =
        item.requested_grams - coalesce((
            SELECT sum(batch.initial_quantity_grams)
            FROM public.inventory_batches AS batch
            WHERE batch.restock_request_item_id = item.id), 0)
    WHERE item.request_id = p_request_id;
    SELECT count(*) INTO receipt_count FROM public.inventory_batches AS batch
    JOIN public.restock_request_items AS item
      ON item.id = batch.restock_request_item_id
    WHERE item.request_id = p_request_id;
    UPDATE public.restock_requests SET
        status = CASE WHEN receipt_count = 0 THEN 'CANCELLED' ELSE 'CLOSED' END,
        cancellation_reason = btrim(p_reason),
        updated_at = now(), closed_at = now()
    WHERE id = p_request_id;
    INSERT INTO public.system_logs
        (actor_user_id, event_type, entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, 'RESTOCK_OUTSTANDING_CANCELLED',
        'restock_requests', p_request_id, 'SUCCESS', 'INFO',
        jsonb_build_object('reason', btrim(p_reason)));
    RETURN jsonb_build_object('id', p_request_id,
        'status', CASE WHEN receipt_count = 0 THEN 'CANCELLED' ELSE 'CLOSED' END);
END;
$$;
COMMIT;

