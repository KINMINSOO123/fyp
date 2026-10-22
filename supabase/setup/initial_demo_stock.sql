-- DEMONSTRATION DATA ONLY. Run the whole file as postgres.
-- This COMMIT persists synthetic stock; unlike verification scripts, it does
-- not roll back on success. Do not use these quantities/dates for real deliveries.
-- Receipt date uses the configured bakery timezone. Expiry = receipt + 7 days
-- is an arbitrary test window for ALL ingredients, not a shelf-life/safety claim.
-- Costs snapshot the demo ingredient master prices (KG required).
-- Bootstrap only: this is not the future authorized Node restock endpoint.
BEGIN;

LOCK TABLE public.bakery_settings, public.user_profiles, public.ingredients IN SHARE MODE;
LOCK TABLE public.inventory, public.inventory_batches, public.inventory_log
    IN SHARE ROW EXCLUSIVE MODE;

DO $stock$
DECLARE
    source_marker constant text := 'DEMO_INITIAL_STOCK_V1';
    operation uuid := gen_random_uuid();
    administrator_id uuid;
    receipt_day date;
    item record;
    ingredient_row public.ingredients%ROWTYPE;
    inventory_row public.inventory%ROWTYPE;
    batch_id_value uuid;
    existing_batches integer;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT count(*) INTO existing_batches FROM public.inventory_batches WHERE source = source_marker;
    IF existing_batches <> 0 THEN
        IF existing_batches = 10 AND (
            SELECT count(*) FROM public.inventory_log AS movement
            JOIN public.inventory_batches AS batch ON batch.id = movement.batch_id
            WHERE batch.source = source_marker AND movement.reason = 'RESTOCK'
              AND movement.change_grams = batch.initial_quantity_grams
        ) = 10 THEN
            RAISE NOTICE 'Demo receipt already exists; nothing added or reset.';
            RETURN;
        END IF;
        RAISE EXCEPTION 'Incomplete demo receipt marker found; inspect before continuing';
    END IF;

    SELECT user_id INTO administrator_id FROM public.user_profiles
    WHERE role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
    ORDER BY user_id LIMIT 1;
    IF administrator_id IS NULL THEN RAISE EXCEPTION 'An ACTIVE SYSTEM_ADMINISTRATOR is required'; END IF;
    SELECT (now() AT TIME ZONE timezone)::date INTO STRICT receipt_day FROM public.bakery_settings;

    FOR item IN SELECT * FROM (VALUES
        ('Bread Flour', 10000::numeric), ('Sugar', 2000::numeric),
        ('Unsalted Butter', 2000::numeric), ('Instant Yeast', 500::numeric),
        ('Milk Powder', 1000::numeric), ('Salt', 500::numeric),
        ('Liquid Whole Egg', 2000::numeric), ('Red Bean Paste', 2000::numeric),
        ('Sweetened Coconut Filling', 2000::numeric), ('Chicken Sausage', 4000::numeric)
    ) AS seed(name, grams) ORDER BY name
    LOOP
        SELECT * INTO STRICT ingredient_row FROM public.ingredients
        WHERE lower(trim(name)) = lower(item.name) AND is_active;
        IF ingredient_row.unit <> 'KG' THEN
            RAISE EXCEPTION 'Demo cost expects KG for %; no stock committed', item.name;
        END IF;
        SELECT * INTO STRICT inventory_row FROM public.inventory
        WHERE ingredient_id = ingredient_row.id FOR UPDATE;
        IF inventory_row.quantity_grams <> 0 OR EXISTS (
            SELECT 1 FROM public.inventory_batches WHERE ingredient_id = ingredient_row.id
        ) THEN
            RAISE EXCEPTION '% already has stock or batches; this bootstrap requires empty inventory', item.name;
        END IF;

        INSERT INTO public.inventory_batches
            (ingredient_id, received_date, expiry_date, initial_quantity_grams,
             remaining_quantity_grams, unit_cost, source, status)
        VALUES (ingredient_row.id, receipt_day, receipt_day + 7, item.grams,
                item.grams, ingredient_row.unit_cost, source_marker, 'ACTIVE')
        RETURNING id INTO batch_id_value;

        UPDATE public.inventory SET quantity_grams = item.grams, updated_by = administrator_id
        WHERE id = inventory_row.id;

        INSERT INTO public.inventory_log
            (operation_id, inventory_id, batch_id, change_grams, reason, effective_date)
        VALUES (operation, inventory_row.id, batch_id_value, item.grams, 'RESTOCK', receipt_day);
    END LOOP;

    INSERT INTO public.system_logs
        (actor_user_id, event_type, outcome, severity, payload)
    VALUES (administrator_id, 'DEMO_STOCK_INITIALIZED', 'SUCCESS', 'INFO',
            jsonb_build_object('source', source_marker, 'operation_id', operation,
                               'batch_count', 10, 'synthetic', true));
END;
$stock$;

COMMIT;

SELECT ingredient.name, batch.received_date, batch.expiry_date,
       batch.initial_quantity_grams, batch.remaining_quantity_grams,
       batch.unit_cost AS snapshot_myr_per_kg,
       stock.quantity_grams AS inventory_snapshot_grams, batch.source
FROM public.inventory_batches AS batch
JOIN public.ingredients AS ingredient ON ingredient.id = batch.ingredient_id
JOIN public.inventory AS stock ON stock.ingredient_id = batch.ingredient_id
WHERE batch.source = 'DEMO_INITIAL_STOCK_V1'
ORDER BY ingredient.name;
