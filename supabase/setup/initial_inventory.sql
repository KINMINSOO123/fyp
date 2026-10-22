-- Initialise missing inventory snapshots for active ingredients with no batches.
-- Does not create stock, receive deliveries or reset any existing balance.
BEGIN;

LOCK TABLE public.ingredients IN SHARE MODE;
LOCK TABLE public.inventory_batches IN SHARE MODE;
LOCK TABLE public.inventory IN SHARE ROW EXCLUSIVE MODE;

DO $setup$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.ingredients WHERE is_active) THEN
        RAISE EXCEPTION 'No active ingredients found; run the ingredient setup first';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.ingredients AS ingredient
        WHERE ingredient.is_active
          AND NOT EXISTS (
              SELECT 1 FROM public.inventory AS stock
              WHERE stock.ingredient_id = ingredient.id
          )
          AND EXISTS (
              SELECT 1 FROM public.inventory_batches AS batch
              WHERE batch.ingredient_id = ingredient.id
          )
    ) THEN
        RAISE EXCEPTION 'An ingredient has batches but no inventory snapshot. Reconcile its batches instead of initialising it to zero.';
    END IF;
END;
$setup$;

INSERT INTO public.inventory (ingredient_id, quantity_grams, updated_by)
SELECT id, 0, NULL FROM public.ingredients WHERE is_active
ON CONFLICT (ingredient_id) DO NOTHING;

COMMIT;

-- Zero initialisation is not a movement: no zero-quantity inventory_log is added.
-- Later restocking must atomically create batches, update these snapshots and
-- record positive RESTOCK movements with actual batch unit-cost snapshots.
SELECT ingredient.name, stock.quantity_grams,
       ingredient.reorder_threshold AS reorder_threshold_grams
FROM public.inventory AS stock
JOIN public.ingredients AS ingredient ON ingredient.id = stock.ingredient_id
WHERE ingredient.is_active
ORDER BY ingredient.name;
