BEGIN;

CREATE TABLE public.bread_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    name text NOT NULL UNIQUE
        CHECK (length(trim(name)) > 0),

    description text
        CHECK (
            description IS NULL
            OR length(trim(description)) > 0
        ),

    display_order integer NOT NULL UNIQUE
        CHECK (display_order >= 0),

    shelf_life_hours integer NOT NULL DEFAULT 24
        CHECK (shelf_life_hours > 0),

    selling_price numeric(12,2) NOT NULL DEFAULT 0
        CHECK (selling_price >= 0),

    is_active boolean NOT NULL DEFAULT true
);

CREATE INDEX idx_bread_categories_active
ON public.bread_categories (is_active, display_order);

ALTER TABLE public.bread_categories
ENABLE ROW LEVEL SECURITY;

COMMIT;