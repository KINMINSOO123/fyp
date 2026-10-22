BEGIN;

CREATE TABLE public.ingredients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    name text NOT NULL UNIQUE
        CHECK (length(trim(name)) > 0),

    unit text NOT NULL DEFAULT 'G'
        CHECK (unit IN ('G', 'KG')),

    unit_cost numeric(12,2) NOT NULL DEFAULT 0
        CHECK (unit_cost >= 0),

    reorder_threshold numeric(14,3) NOT NULL DEFAULT 0
        CHECK (reorder_threshold >= 0),

    is_active boolean NOT NULL DEFAULT true
);

CREATE INDEX idx_ingredients_active
ON public.ingredients (is_active, name);

ALTER TABLE public.ingredients
ENABLE ROW LEVEL SECURITY;

COMMIT;