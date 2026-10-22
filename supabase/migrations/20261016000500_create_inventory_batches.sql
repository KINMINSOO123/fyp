BEGIN;

CREATE TABLE public.inventory_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    ingredient_id uuid NOT NULL
        REFERENCES public.ingredients(id)
        ON DELETE RESTRICT,

    received_date date NOT NULL,

    expiry_date date NOT NULL,

    initial_quantity_grams numeric(14,3) NOT NULL
        CHECK (initial_quantity_grams > 0),

    remaining_quantity_grams numeric(14,3) NOT NULL
        CHECK (
            remaining_quantity_grams >= 0
            AND remaining_quantity_grams <= initial_quantity_grams
        ),

    unit_cost numeric(12,2) NOT NULL
        CHECK (unit_cost >= 0),

    source text
        CHECK (
            source IS NULL
            OR length(trim(source)) > 0
        ),

    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (
            status IN (
                'ACTIVE',
                'DEPLETED',
                'EXPIRED',
                'DISCARDED'
            )
        ),

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT inventory_batches_dates_check
        CHECK (expiry_date > received_date),

    CONSTRAINT inventory_batches_active_quantity_check
        CHECK (
            status <> 'ACTIVE'
            OR remaining_quantity_grams > 0
        ),

    CONSTRAINT inventory_batches_depleted_quantity_check
        CHECK (
            status <> 'DEPLETED'
            OR remaining_quantity_grams = 0
        )
);

CREATE INDEX idx_inventory_batches_fifo
ON public.inventory_batches (
    ingredient_id,
    received_date,
    id
)
WHERE status = 'ACTIVE';

CREATE INDEX idx_inventory_batches_fefo
ON public.inventory_batches
    (ingredient_id, expiry_date, received_date, id)
WHERE status = 'ACTIVE';

CREATE INDEX idx_inventory_batches_expiry
ON public.inventory_batches (status, expiry_date);

ALTER TABLE public.inventory_batches
ENABLE ROW LEVEL SECURITY;

COMMIT;