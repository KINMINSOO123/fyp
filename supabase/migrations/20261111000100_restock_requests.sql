BEGIN;

CREATE TABLE public.restock_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    production_date date NOT NULL,
    requester_user_id uuid NOT NULL REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    desired_quantities jsonb NOT NULL CHECK (jsonb_typeof(desired_quantities) = 'array'),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN
        ('PENDING', 'PARTIALLY_RECEIVED', 'FULFILLED', 'CANCELLED', 'CLOSED')),
    cancellation_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    CONSTRAINT restock_close_check CHECK (
        (status IN ('PENDING', 'PARTIALLY_RECEIVED') AND closed_at IS NULL)
        OR (status IN ('FULFILLED', 'CANCELLED', 'CLOSED') AND closed_at IS NOT NULL))
);
CREATE UNIQUE INDEX restock_one_active_per_date
    ON public.restock_requests (production_date)
    WHERE status IN ('PENDING', 'PARTIALLY_RECEIVED');
CREATE INDEX restock_requests_status_date
    ON public.restock_requests (status, production_date, created_at DESC);
ALTER TABLE public.restock_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.restock_request_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id uuid NOT NULL REFERENCES public.restock_requests(id) ON DELETE RESTRICT,
    ingredient_id uuid NOT NULL REFERENCES public.ingredients(id) ON DELETE RESTRICT,
    requested_grams numeric(14,3) NOT NULL CHECK (requested_grams > 0),
    cancelled_grams numeric(14,3) NOT NULL DEFAULT 0
        CHECK (cancelled_grams >= 0 AND cancelled_grams <= requested_grams),
    UNIQUE (request_id, ingredient_id),
    UNIQUE (id, ingredient_id)
);
CREATE INDEX restock_items_request ON public.restock_request_items (request_id);
ALTER TABLE public.restock_request_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_batches
    ADD COLUMN restock_request_item_id uuid,
    ADD COLUMN restock_receipt_key uuid UNIQUE,
    ADD CONSTRAINT inventory_batch_restock_item_ingredient_fk
      FOREIGN KEY (restock_request_item_id, ingredient_id)
      REFERENCES public.restock_request_items(id, ingredient_id) ON DELETE RESTRICT,
    ADD CONSTRAINT inventory_batch_restock_key_check
      CHECK ((restock_request_item_id IS NULL) = (restock_receipt_key IS NULL));
CREATE INDEX inventory_batches_restock_item
    ON public.inventory_batches (restock_request_item_id)
    WHERE restock_request_item_id IS NOT NULL;

-- Compact authoritative comparison snapshot; names are presentation data.
CREATE FUNCTION public.restock_plan_snapshot(p_date date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb;
BEGIN
    IF p_date IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.bread_categories WHERE is_active
    ) OR EXISTS (
        SELECT 1 FROM public.bread_categories AS category
        LEFT JOIN public.daily_predictions AS prediction
          ON prediction.bread_category_id = category.id
         AND prediction.target_date = p_date
        WHERE category.is_active AND prediction.id IS NULL
    ) OR EXISTS (
        SELECT 1 FROM public.bread_categories AS category
        WHERE category.is_active AND NOT EXISTS (
            SELECT 1 FROM public.recipes WHERE bread_category_id = category.id
        )
    ) OR EXISTS (
        SELECT 1 FROM public.recipes AS recipe
        JOIN public.bread_categories AS category
          ON category.id = recipe.bread_category_id AND category.is_active
        JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
        WHERE NOT ingredient.is_active
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Prediction or active recipe is incomplete.';
    END IF;
    WITH desired AS (
        SELECT category.id AS bread_category_id, category.display_order,
            CASE WHEN production.id IS NOT NULL THEN NULL::integer
                 WHEN decision.id IS NOT NULL THEN decision.final_selected_qty
                 ELSE prediction.predicted_units_sold END AS desired_qty
        FROM public.bread_categories AS category
        JOIN public.daily_predictions AS prediction
          ON prediction.bread_category_id = category.id
         AND prediction.target_date = p_date
        LEFT JOIN public.production_decisions AS decision
          ON decision.prediction_id = prediction.id
        LEFT JOIN public.daily_production AS production
          ON production.production_decision_id = decision.id
        WHERE category.is_active
    ), required AS (
        SELECT recipe.ingredient_id,
            sum(recipe.grams_per_unit * desired.desired_qty) AS required_grams
        FROM desired JOIN public.recipes AS recipe
          ON recipe.bread_category_id = desired.bread_category_id
        WHERE desired.desired_qty IS NOT NULL
        GROUP BY recipe.ingredient_id
    ), available AS (
        SELECT batch.ingredient_id, sum(batch.remaining_quantity_grams) AS available_grams
        FROM public.inventory_batches AS batch
        WHERE batch.status = 'ACTIVE' AND batch.received_date <= p_date
          AND batch.expiry_date >= p_date
        GROUP BY batch.ingredient_id
    ), shortage AS (
        SELECT required.ingredient_id,
            required.required_grams - coalesce(available.available_grams, 0) AS additional_grams
        FROM required LEFT JOIN available
          ON available.ingredient_id = required.ingredient_id
        WHERE required.required_grams > coalesce(available.available_grams, 0)
    )
    SELECT jsonb_build_object(
        'desiredQuantities', coalesce((SELECT jsonb_agg(
            jsonb_build_object('breadCategoryId', bread_category_id,
                'desiredQty', desired_qty)
            ORDER BY display_order, bread_category_id)
            FROM desired WHERE desired_qty IS NOT NULL), '[]'::jsonb),
        'shortages', coalesce((SELECT jsonb_agg(
            jsonb_build_object('ingredientId', ingredient_id,
                'additionalGrams', additional_grams)
            ORDER BY ingredient_id) FROM shortage), '[]'::jsonb)
    ) INTO result;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.restock_plan_snapshot(date)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restock_plan_snapshot(date) TO service_role;

CREATE FUNCTION public.submit_restock_request(
    p_actor_user_id uuid, p_production_date date, p_expected_plan jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE snapshot jsonb; request_id_value uuid; item jsonb; bakery_day date;
BEGIN
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active manager required.';
    END IF;
    IF p_production_date IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Production date required.';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-production:' || p_production_date::text, 0));
    SELECT (now() AT TIME ZONE timezone)::date INTO bakery_day
      FROM public.bakery_settings WHERE singleton_guard = true FOR SHARE;
    IF bakery_day IS NULL OR p_production_date <> bakery_day + 1 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Next production date required.';
    END IF;
    snapshot := public.restock_plan_snapshot(p_production_date);
    IF p_expected_plan IS DISTINCT FROM snapshot THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'Production or stock changed; refresh the restock preview.';
    END IF;
    IF jsonb_array_length(snapshot->'shortages') = 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'No ingredient shortage remains.';
    END IF;
    INSERT INTO public.restock_requests
        (production_date, requester_user_id, desired_quantities)
    VALUES (p_production_date, p_actor_user_id, snapshot->'desiredQuantities')
    RETURNING id INTO request_id_value;
    FOR item IN SELECT value FROM jsonb_array_elements(snapshot->'shortages') AS entry(value)
    LOOP
        INSERT INTO public.restock_request_items
            (request_id, ingredient_id, requested_grams)
        VALUES (request_id_value, (item->>'ingredientId')::uuid,
            (item->>'additionalGrams')::numeric);
    END LOOP;
    INSERT INTO public.system_logs
        (actor_user_id, event_type, entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, 'RESTOCK_REQUEST_SUBMITTED',
        'restock_requests', request_id_value, 'SUCCESS', 'INFO',
        jsonb_build_object('productionDate', p_production_date,
            'plan', snapshot));
    RETURN jsonb_build_object('id', request_id_value,
        'productionDate', p_production_date, 'status', 'PENDING');
END;
$$;
REVOKE ALL ON FUNCTION public.submit_restock_request(uuid, date, jsonb)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_restock_request(uuid, date, jsonb)
    TO service_role;

-- Calls the existing inventory receipt once in this transaction, then links
-- that batch and derives fulfilment. No status operation changes stock.
CREATE FUNCTION public.receive_restock_batch(
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
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
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
        p_actor_user_id, 'RECEIVE_BATCH', p_payload);
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
REVOKE ALL ON FUNCTION public.receive_restock_batch(uuid, uuid, uuid, jsonb)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receive_restock_batch(uuid, uuid, uuid, jsonb)
    TO service_role;

CREATE FUNCTION public.cancel_restock_outstanding(
    p_actor_user_id uuid, p_request_id uuid, p_reason text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restock_requests%ROWTYPE; receipt_count integer;
BEGIN
    PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
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
REVOKE ALL ON FUNCTION public.cancel_restock_outstanding(uuid, uuid, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_restock_outstanding(uuid, uuid, text)
    TO service_role;

COMMIT;
