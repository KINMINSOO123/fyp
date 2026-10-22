-- Read-only setup check. Run after initial_demo_stock.sql as postgres.
-- Expected for the initial catalogue: 10 rows, all three check columns PASS.
-- Uses today's date in the configured bakery timezone, not the computer timezone.
-- Does not update stock, refresh expiry status or execute a production workflow.
WITH expected(name) AS (
    VALUES ('Bread Flour'), ('Sugar'), ('Unsalted Butter'), ('Instant Yeast'),
           ('Milk Powder'), ('Salt'), ('Liquid Whole Egg'), ('Red Bean Paste'),
           ('Sweetened Coconut Filling'), ('Chicken Sausage')
), context AS (
    SELECT (now() AT TIME ZONE timezone)::date AS production_date
    FROM public.bakery_settings
), usable AS (
    SELECT batch.ingredient_id,
        SUM(batch.remaining_quantity_grams) AS usable_grams
    FROM public.inventory_batches AS batch
    CROSS JOIN context
    WHERE batch.status = 'ACTIVE'
      AND batch.received_date <= context.production_date
      AND batch.expiry_date >= context.production_date
      AND batch.remaining_quantity_grams > 0
    GROUP BY batch.ingredient_id
), demo_batches AS (
    SELECT ingredient_id, count(*) AS batch_count,
           min(id::text)::uuid AS batch_id
    FROM public.inventory_batches
    WHERE source = 'DEMO_INITIAL_STOCK_V1'
    GROUP BY ingredient_id
), receipt_checks AS (
    SELECT batch.id AS batch_id,
        count(movement.id) AS restock_count,
        bool_and(
            movement.change_grams = batch.initial_quantity_grams
            AND movement.effective_date = batch.received_date
            AND stock.ingredient_id = batch.ingredient_id
        ) AS receipt_matches
    FROM public.inventory_batches AS batch
    LEFT JOIN public.inventory_log AS movement
        ON movement.batch_id = batch.id AND movement.reason = 'RESTOCK'
    LEFT JOIN public.inventory AS stock ON stock.id = movement.inventory_id
    WHERE batch.source = 'DEMO_INITIAL_STOCK_V1'
    GROUP BY batch.id
)
SELECT expected.name AS ingredient,
    (SELECT production_date FROM context) AS checked_date,
    stock.quantity_grams AS inventory_grams,
    COALESCE(usable.usable_grams, 0) AS eligible_batch_grams,
    stock.quantity_grams - COALESCE(usable.usable_grams, 0) AS difference_grams,
    CASE WHEN ingredient.id IS NOT NULL AND demo.batch_count = 1
        THEN 'PASS' ELSE 'MISSING OR DUPLICATE DEMO BATCH' END AS batch_check,
    CASE WHEN receipt.restock_count = 1 AND receipt.receipt_matches
        THEN 'PASS' ELSE 'CHECK RESTOCK MOVEMENT' END AS receipt_check,
    CASE WHEN (SELECT count(*) FROM context) <> 1 THEN 'CHECK BAKERY SETTINGS'
         WHEN stock.id IS NULL THEN 'MISSING INVENTORY ROW'
         WHEN stock.quantity_grams = COALESCE(usable.usable_grams, 0) THEN 'PASS'
         ELSE 'RECONCILIATION NEEDED' END AS balance_check
FROM expected
LEFT JOIN public.ingredients AS ingredient
    ON lower(trim(ingredient.name)) = lower(expected.name)
LEFT JOIN public.inventory AS stock ON stock.ingredient_id = ingredient.id
LEFT JOIN usable ON usable.ingredient_id = ingredient.id
LEFT JOIN demo_batches AS demo ON demo.ingredient_id = ingredient.id
LEFT JOIN receipt_checks AS receipt ON receipt.batch_id = demo.batch_id
ORDER BY expected.name;

-- A later expiry can legitimately make eligible stock lower than an unchanged
-- cached inventory balance. Investigate/reconcile it; never extend expiry dates
-- simply to make this check pass. This is not a general inventory-ledger audit.
