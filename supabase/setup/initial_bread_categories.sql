-- Initial demonstration catalogue selected 2026-10-21.
-- Prices are chosen simulation inputs in MYR per single bun, not national
-- averages or claims about the most popular products in Malaysia.
-- Menu references consulted:
-- https://happyangelscakehouse.com/collections/bun
--   Red Bean Bun and Coconut Bun listed at RM2.20 each.
-- https://shop.rtpastry.com/product-category/bread/
--   Butter Sugar Bun (Special) listed at RM3.60.
-- https://littleovenbakery.oddle.me/en_MY
--   Indexed menu lists Sausage Roll at RM2.80 per piece.
-- Selected rounded demo prices: butter sugar RM3, red bean/coconut RM2.50,
-- chicken sausage RM3. Product sizes and prices vary by bakery.
-- 24-hour shelf life is a simulation assumption inherited from the plan,
-- not a food-safety determination for these products or their storage conditions.
-- Display order is a deliberate demo allocation priority, not popularity rank.
-- Four categories are starting examples, not a system limit.

BEGIN;

-- Serialize order assignment while preserving existing catalogue entries.
LOCK TABLE public.bread_categories IN SHARE ROW EXCLUSIVE MODE;

WITH seed(seed_order, name, description, selling_price) AS (
    VALUES
        (1, 'Butter Sugar Bun', 'Single soft bun with butter and sugar topping.', 3.00::numeric),
        (2, 'Red Bean Bun', 'Single soft bun filled with red bean paste.', 2.50::numeric),
        (3, 'Coconut Bun', 'Single soft bun filled with sweetened coconut.', 2.50::numeric),
        (4, 'Chicken Sausage Bun', 'Single soft bread roll containing chicken sausage.', 3.00::numeric)
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
SELECT name, description, assigned_order::integer, 24, selling_price, true
FROM numbered ORDER BY seed_order;

COMMIT;

-- Re-running inserts no duplicate names and does not overwrite existing rows.
-- An existing inactive category is not silently reactivated.
SELECT name, selling_price, display_order, shelf_life_hours, is_active
FROM public.bread_categories
ORDER BY display_order;
