BEGIN;

CREATE TABLE public.sales_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    daily_result_id uuid NOT NULL
        REFERENCES public.daily_results(id) ON DELETE RESTRICT,
    sale_time time NOT NULL,
    time_slot text NOT NULL
        CHECK (time_slot IN ('MORNING', 'AFTERNOON', 'EVENING')),
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price numeric(12,2) NOT NULL
        CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric),
    subtotal numeric(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sales_result_slot
    ON public.sales_transactions (daily_result_id, time_slot, sale_time);

ALTER TABLE public.sales_transactions ENABLE ROW LEVEL SECURITY;

-- Date and bread category are derived through daily_result_id.
-- Later Node POS logic must preserve the transaction-time unit-price snapshot,
-- validate the sale time/slot against bakery settings, and reconcile summed
-- quantities and subtotals with daily_results.units_sold and revenue.
-- Sales, results, production, inventory movements and simulation history must
-- commit in one transaction. These workflow checks are not implemented here.
-- These are simulated sales records, not customer orders or payment processing.
-- Reports use either these details or daily totals, never add both together.

COMMIT;
