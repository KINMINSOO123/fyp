-- Demonstration ingredient catalogue, selected 2026-10-21.
-- All master prices below are explicit simulation assumptions in MYR/kg.
-- They are not supplier quotes or verified current market averages.
-- Sanity-check reference: https://take.app/60380752213/search?page=2
-- Listed examples included high-protein flour 1kg RM4.20, unsalted butter
-- 250g RM8.50 (RM34/kg), and chicken frank 40g x 8 RM9 (RM28.125/kg).
-- Other demo inputs are chosen assumptions, not sourced price claims.
-- Reorder thresholds are provisional grams, to tune after workload testing.
-- Recipes will use grams per bun, including egg/sausage edible mass.
-- Coconut filling is a purchased/prepared ingredient; do not also count its
-- internal coconut/sugar components in the same recipe.
-- Five ingredients were only examples in the plan, not a catalogue limit.

BEGIN;
LOCK TABLE public.ingredients IN SHARE ROW EXCLUSIVE MODE;

WITH seed(name, unit_cost, reorder_threshold) AS (
    VALUES
        ('Bread Flour', 5.00::numeric, 5000::numeric),
        ('Sugar', 3.00::numeric, 1000::numeric),
        ('Unsalted Butter', 36.00::numeric, 1000::numeric),
        ('Instant Yeast', 20.00::numeric, 100::numeric),
        ('Milk Powder', 28.00::numeric, 500::numeric),
        ('Salt', 2.00::numeric, 100::numeric),
        ('Liquid Whole Egg', 12.00::numeric, 1000::numeric),
        ('Red Bean Paste', 10.00::numeric, 1000::numeric),
        ('Sweetened Coconut Filling', 12.00::numeric, 1000::numeric),
        ('Chicken Sausage', 28.00::numeric, 1000::numeric)
)
INSERT INTO public.ingredients (name, unit, unit_cost, reorder_threshold, is_active)
SELECT seed.name, 'KG', seed.unit_cost, seed.reorder_threshold, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1 FROM public.ingredients AS existing
    WHERE lower(trim(existing.name)) = lower(seed.name)
);

COMMIT;

-- No stock or delivery batches are created. Master costs do not rewrite
-- historical batch costs. Actual consumption cost uses FEFO batch snapshots.
-- Re-running preserves any existing prices, units, thresholds and active status.
SELECT name, unit, unit_cost AS reference_myr_per_unit,
       reorder_threshold AS reorder_threshold_grams, is_active
FROM public.ingredients ORDER BY name;
