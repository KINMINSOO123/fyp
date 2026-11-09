-- Demonstration inventory requirements per ONE bun, not a validated baking recipe.
-- Quantities are simulation assumptions, not measurements from a real bakery.
-- Water is treated as an untracked utility in this simplified inventory model;
-- these grams therefore do not represent total dough or finished-product weight.
-- Utilities, labour and packaging are outside these ingredient-cost estimates.
-- Butter Sugar Bun includes its topping in the total butter/sugar quantities.
-- Coconut filling is a prepared ingredient; do not count its internal sugar twice.
-- The four additional toppings/fillings are prepared ingredients; do not
-- count their internal ingredients again. No stock is added or deducted.
-- Run after the category and ingredient seeds, then initialise inventory
-- and configure cold-start bases before generating predictions.

BEGIN;
LOCK TABLE public.bread_categories IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.ingredients IN SHARE MODE;
LOCK TABLE public.recipes IN SHARE ROW EXCLUSIVE MODE;

DO $seed$
DECLARE
    item record;
    category_id_value uuid;
    ingredient_id_value uuid;
    existing_grams numeric;
BEGIN
    FOR item IN
        WITH categories(category_name) AS (
            VALUES ('Butter Sugar Bun'), ('Red Bean Bun'),
                   ('Coconut Bun'), ('Chicken Sausage Bun'),
                   ('Cheese Bun'), ('Custard Bun'),
                   ('Mexican Coffee Bun'), ('Chicken Floss Bun')
        ), shared(ingredient_name, grams) AS (
            VALUES ('Bread Flour', 50.000::numeric),
                   ('Sugar', 6.000::numeric),
                   ('Unsalted Butter', 5.000::numeric),
                   ('Instant Yeast', 0.600::numeric),
                   ('Milk Powder', 2.000::numeric),
                   ('Salt', 0.800::numeric),
                   ('Liquid Whole Egg', 5.000::numeric)
        ), expected AS (
            SELECT category_name, ingredient_name,
                CASE
                    WHEN category_name = 'Butter Sugar Bun' AND ingredient_name = 'Sugar' THEN 10.000
                    WHEN category_name = 'Butter Sugar Bun' AND ingredient_name = 'Unsalted Butter' THEN 8.000
                    ELSE grams
                END AS grams
            FROM categories CROSS JOIN shared
            UNION ALL
            SELECT * FROM (VALUES
                ('Red Bean Bun', 'Red Bean Paste', 20.000::numeric),
                ('Coconut Bun', 'Sweetened Coconut Filling', 20.000::numeric),
                ('Chicken Sausage Bun', 'Chicken Sausage', 40.000::numeric),
                ('Cheese Bun', 'Cheese Topping', 15.000::numeric),
                ('Custard Bun', 'Custard Filling', 20.000::numeric),
                ('Mexican Coffee Bun', 'Coffee Topping Mix', 15.000::numeric),
                ('Chicken Floss Bun', 'Chicken Floss', 20.000::numeric)
            ) AS filling(category_name, ingredient_name, grams)
        )
        SELECT * FROM expected ORDER BY category_name, ingredient_name
    LOOP
        -- Match the seed names while allowing harmless case/outer-space changes.
        -- STRICT also stops on ambiguous matches rather than choosing arbitrarily.
        SELECT id INTO STRICT category_id_value FROM public.bread_categories
        WHERE lower(trim(name)) = lower(item.category_name);
        SELECT id INTO STRICT ingredient_id_value FROM public.ingredients
        WHERE lower(trim(name)) = lower(item.ingredient_name) AND is_active;

        SELECT grams_per_unit INTO existing_grams FROM public.recipes
        WHERE bread_category_id = category_id_value AND ingredient_id = ingredient_id_value;
        IF FOUND AND existing_grams IS DISTINCT FROM item.grams THEN
            RAISE EXCEPTION 'Existing recipe differs for % / %: % g vs proposed % g. No changes committed.',
                item.category_name, item.ingredient_name, existing_grams, item.grams;
        END IF;

        INSERT INTO public.recipes (bread_category_id, ingredient_id, grams_per_unit)
        VALUES (category_id_value, ingredient_id_value, item.grams)
        ON CONFLICT (bread_category_id, ingredient_id) DO NOTHING;
    END LOOP;

    -- The newly seeded categories remain inactive until every expected
    -- ingredient link above has been inserted or verified unchanged.
    UPDATE public.bread_categories
    SET is_active = true
    WHERE lower(trim(name)) IN (
        'cheese bun', 'custard bun', 'mexican coffee bun', 'chicken floss bun'
    );
END;
$seed$;

COMMIT;

-- Expected demonstration recipe rows: 63 (7 for Butter Sugar Bun and
-- 8 for each of the other seven categories).
-- Existing additional recipe rows are preserved and visible for review below.
SELECT category.name AS bread_category, ingredient.name AS ingredient,
       recipe.grams_per_unit
FROM public.recipes AS recipe
JOIN public.bread_categories AS category ON category.id = recipe.bread_category_id
JOIN public.ingredients AS ingredient ON ingredient.id = recipe.ingredient_id
WHERE lower(trim(category.name)) IN
    ('butter sugar bun', 'red bean bun', 'coconut bun', 'chicken sausage bun',
     'cheese bun', 'custard bun', 'mexican coffee bun', 'chicken floss bun')
ORDER BY category.display_order, ingredient.name;

-- The final result shows the activation and number of linked ingredients.
SELECT category.name AS bread_category, category.is_active,
       count(recipe.id) AS recipe_ingredient_count
FROM public.bread_categories AS category
LEFT JOIN public.recipes AS recipe ON recipe.bread_category_id = category.id
WHERE lower(trim(category.name)) IN
    ('butter sugar bun', 'red bean bun', 'coconut bun', 'chicken sausage bun',
     'cheese bun', 'custard bun', 'mexican coffee bun', 'chicken floss bun')
GROUP BY category.id, category.name, category.is_active, category.display_order
ORDER BY category.display_order;
