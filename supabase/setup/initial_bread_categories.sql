-- Initial four-category demonstration catalogue selected 2026-10-21.
-- Expanded to eight demonstration categories on 2026-11-09.
-- Prices are chosen simulation inputs in MYR per single bun, not national
-- averages or claims about the most popular products in Malaysia.
-- Menu references consulted:
-- https://happyangelscakehouse.com/collections/bun
--   Red Bean Bun and Coconut Bun listed at RM2.20 each.
-- https://shop.rtpastry.com/product-category/bread/
--   Butter Sugar Bun (Special), Cheese Bread, Custard Bun, Mexican Coffee Bun
--   and Chicken Floss Bun inform the selected demo names and prices.
-- https://littleovenbakery.oddle.me/en_MY
--   Indexed menu lists Sausage Roll at RM2.80 per piece.
-- Selected rounded demo prices: butter sugar RM3, red bean/coconut RM2.50,
-- chicken sausage RM3; cheese RM3.80, custard RM3, Mexican coffee RM4,
-- chicken floss RM3.90. Product sizes and prices vary by bakery.
-- 24-hour shelf life is a simulation assumption inherited from the plan,
-- not a food-safety determination for these products or their storage conditions.
-- Display order is a deliberate demo allocation priority, not popularity rank.
-- Eight categories are examples, not a system limit. The original four
-- remain ACTIVE. The four new categories are inserted INACTIVE and the
-- initial_recipes.sql setup activates them after their ingredient links exist.
-- Run prediction_context_settings.sql afterwards for cold-start bases.

BEGIN;

-- Serialize order assignment while preserving existing catalogue entries.
LOCK TABLE public.bread_categories IN SHARE ROW EXCLUSIVE MODE;

WITH seed(seed_order, name, description, selling_price, is_active) AS (
    VALUES
        (1, 'Butter Sugar Bun', 'Single soft bun with butter and sugar topping.', 3.00::numeric, true),
        (2, 'Red Bean Bun', 'Single soft bun filled with red bean paste.', 2.50::numeric, true),
        (3, 'Coconut Bun', 'Single soft bun filled with sweetened coconut.', 2.50::numeric, true),
        (4, 'Chicken Sausage Bun', 'Single soft bread roll containing chicken sausage.', 3.00::numeric, true),
        (5, 'Cheese Bun', 'Single soft bun with a cheese topping.', 3.80::numeric, false),
        (6, 'Custard Bun', 'Single soft bun with custard filling.', 3.00::numeric, false),
        (7, 'Mexican Coffee Bun', 'Single soft bun with a coffee-flavoured topping.', 4.00::numeric, false),
        (8, 'Chicken Floss Bun', 'Single soft bun with chicken floss topping.', 3.90::numeric, false)
), missing AS (
    SELECT seed.* FROM seed
    WHERE NOT EXISTS (
        SELECT 1 FROM public.bread_categories AS existing
        WHERE lower(trim(existing.name)) = lower(seed.name)
    )
), numbered AS (
    SELECT missing.*,
        (SELECT COALESCE(max(display_order), 0) FROM public.bread_categories)
        + row_number() OVER (ORDER BY seed_order) AS assigned_order
    FROM missing
)
INSERT INTO public.bread_categories
    (name, description, display_order, shelf_life_hours, selling_price, is_active)
SELECT name, description, assigned_order::integer, 24, selling_price, is_active
FROM numbered ORDER BY seed_order;

COMMIT;

-- Re-running inserts no duplicate names and does not overwrite existing rows.
-- An existing inactive category is not silently reactivated.
SELECT name, selling_price, display_order, shelf_life_hours, is_active
FROM public.bread_categories
ORDER BY display_order;
