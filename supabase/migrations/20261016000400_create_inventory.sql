BEGIN;

CREATE TABLE public.inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    ingredient_id uuid NOT NULL UNIQUE
        REFERENCES public.ingredients(id)
        ON DELETE RESTRICT,

    quantity_grams numeric(14,3) NOT NULL DEFAULT 0
        CHECK (quantity_grams >= 0),

    updated_by uuid
        REFERENCES public.user_profiles(user_id)
        ON DELETE RESTRICT,

    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_inventory_updated_at
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.inventory
ENABLE ROW LEVEL SECURITY;

COMMIT;