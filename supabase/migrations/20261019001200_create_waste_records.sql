BEGIN;

CREATE TABLE public.waste_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    daily_result_id uuid NOT NULL
        REFERENCES public.daily_results(id) ON DELETE RESTRICT,
    waste_date date NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    disposal_reason text NOT NULL CHECK (length(trim(disposal_reason)) > 0),
    confirmed_by uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_waste_result_date
    ON public.waste_records (daily_result_id, waste_date);

ALTER TABLE public.waste_records ENABLE ROW LEVEL SECURITY;

-- Bread category is derived through daily_result_id.
-- Later Node allocation logic must authorize an ACTIVE Bakery Manager, derive
-- confirmed_by server-side and validate waste_date >= the linked result date.
-- Lock the same daily_results row used for donation allocation, verify enough
-- remaining unallocated leftovers, then insert this record and reduce that
-- balance in one transaction. Maintain:
-- leftover = donated + wasted + remaining_unallocated.
-- This table alone does not implement these cross-row checks or update balances.
-- These records count discarded bread in units, not ingredient losses in grams.
-- Ingredients were consumed during production; recording bread waste must not
-- deduct those ingredients again. Unsold or donated bread is not automatically
-- classified as discarded waste.

COMMIT;
