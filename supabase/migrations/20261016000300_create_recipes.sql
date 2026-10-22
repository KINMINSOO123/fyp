BEGIN;

CREATE TABLE public.recipes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id)
        ON DELETE RESTRICT,

    ingredient_id uuid NOT NULL
        REFERENCES public.ingredients(id)
        ON DELETE RESTRICT,

    grams_per_unit numeric(14,3) NOT NULL
        CHECK (grams_per_unit > 0),

    CONSTRAINT recipes_category_ingredient_unique
        UNIQUE (bread_category_id, ingredient_id)
);

CREATE INDEX idx_recipes_ingredient
ON public.recipes (ingredient_id);

ALTER TABLE public.recipes
ENABLE ROW LEVEL SECURITY;

COMMIT;