-- Read-only. Run as postgres in Supabase SQL Editor.
-- READY means this configuration check passed, not that the app is implemented.
-- No demo data is inserted. Empty catalogues should report NEEDS SETUP.
WITH checks(check_number, setup_item, ready, next_action) AS (
    SELECT 1, 'Bakery configuration',
        (SELECT count(*) = 1 FROM public.bakery_settings),
        'Create exactly one bakery settings row; review its name, hours and timezone.'
    UNION ALL
    SELECT 2, 'Active System Administrator', EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
    ), 'Create or activate the intended administrator profile.'
    UNION ALL
    SELECT 3, 'Active Bakery Manager', EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE role = 'BAKERY_MANAGER' AND account_status = 'ACTIVE'
    ), 'Create or activate the intended manager profile.'
    UNION ALL
    SELECT 4, 'Active bread categories', EXISTS (
        SELECT 1 FROM public.bread_categories WHERE is_active
    ), 'Add the initial bread catalogue; four categories are examples, not a limit.'
    UNION ALL
    SELECT 5, 'Active ingredients', EXISTS (
        SELECT 1 FROM public.ingredients WHERE is_active
    ), 'Add ingredients with consistent units, reference prices and reorder thresholds.'
    UNION ALL
    SELECT 6, 'Recipes for all active categories',
        EXISTS (SELECT 1 FROM public.bread_categories WHERE is_active)
        AND NOT EXISTS (
            SELECT 1 FROM public.bread_categories AS category
            WHERE category.is_active AND NOT EXISTS (
                SELECT 1 FROM public.recipes AS recipe
                WHERE recipe.bread_category_id = category.id
            )
        ) AND NOT EXISTS (
            SELECT 1 FROM public.recipes AS recipe
            JOIN public.bread_categories AS category ON category.id = recipe.bread_category_id
            JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
            WHERE category.is_active AND NOT ingredient.is_active
        ), 'Add grams-per-unit recipe rows and resolve inactive ingredients in active recipes.'
    UNION ALL
    SELECT 7, 'Inventory rows for all active ingredients',
        EXISTS (SELECT 1 FROM public.ingredients WHERE is_active)
        AND NOT EXISTS (
            SELECT 1 FROM public.ingredients AS ingredient
            WHERE ingredient.is_active AND NOT EXISTS (
                SELECT 1 FROM public.inventory AS stock WHERE stock.ingredient_id = ingredient.id
            )
        ), 'Initialize missing inventory rows; zero stock is valid. Do not invent stock balances.'
    UNION ALL
    SELECT 8, 'Model confidence threshold configuration', EXISTS (
        SELECT 1 FROM public.system_settings
        WHERE setting_key = 'prediction.low_confidence_threshold'
          AND data_type = 'NUMERIC'
          AND CASE WHEN jsonb_typeof(setting_value) = 'number'
              THEN (setting_value::text)::numeric BETWEEN 0 AND 100
              ELSE false END
    ), 'Set a numeric threshold between 0 and 100; the initial planned value is 75.'
)
SELECT check_number, setup_item,
    CASE WHEN ready THEN 'READY' ELSE 'NEEDS SETUP' END AS status,
    CASE WHEN ready THEN NULL ELSE next_action END AS next_action
FROM checks ORDER BY check_number;

-- Recipe completeness here means row presence and active ingredients only;
-- correctness of ingredient amounts still requires review.
-- Batch/snapshot reconciliation, FEFO restocking, cold-start factors and base
-- quantities, external credentials and backend permissions are separate work.
