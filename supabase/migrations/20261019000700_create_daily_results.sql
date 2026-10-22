BEGIN;

CREATE TABLE public.daily_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    result_date date NOT NULL,
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    prediction_id uuid NOT NULL UNIQUE,
    daily_production_id uuid NOT NULL UNIQUE,
    predicted_units_sold integer NOT NULL CHECK (predicted_units_sold >= 0),
    produced integer NOT NULL CHECK (produced >= 0),
    units_sold integer NOT NULL CHECK (units_sold >= 0 AND units_sold <= produced),
    lost_sales integer NOT NULL DEFAULT 0 CHECK (lost_sales >= 0),
    estimated_demand integer GENERATED ALWAYS AS (units_sold + lost_sales) STORED,
    leftover integer GENERATED ALWAYS AS (produced - units_sold) STORED,
    remaining_unallocated_leftover integer NOT NULL
        CHECK (
            remaining_unallocated_leftover >= 0
            AND remaining_unallocated_leftover <= produced - units_sold
        ),
    leftover_rate_pct numeric(7,4) GENERATED ALWAYS AS (
        CASE WHEN produced > 0
            THEN (produced - units_sold)::numeric / produced * 100
            ELSE NULL
        END
    ) STORED,
    sales_prediction_error integer GENERATED ALWAYS AS (
        units_sold - predicted_units_sold
    ) STORED,
    notes text,
    revenue numeric(14,2) NOT NULL DEFAULT 0
        CHECK (revenue >= 0 AND revenue <> 'NaN'::numeric),
    ingredient_cost numeric(14,2) NOT NULL DEFAULT 0
        CHECK (ingredient_cost >= 0 AND ingredient_cost <> 'NaN'::numeric),
    gross_profit numeric(14,2) GENERATED ALWAYS AS (revenue - ingredient_cost) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT daily_results_date_category_key
        UNIQUE (result_date, bread_category_id),
    CONSTRAINT daily_results_id_date_category_key
        UNIQUE (id, result_date, bread_category_id),
    CONSTRAINT daily_results_prediction_context_fk
        FOREIGN KEY (prediction_id, result_date, bread_category_id)
        REFERENCES public.daily_predictions (id, target_date, bread_category_id)
        ON DELETE RESTRICT,
    CONSTRAINT daily_results_production_context_fk
        FOREIGN KEY (daily_production_id, result_date, bread_category_id)
        REFERENCES public.daily_production (id, production_date, bread_category_id)
        ON DELETE RESTRICT
);

ALTER TABLE public.daily_results ENABLE ROW LEVEL SECURITY;

-- Later Node-owned POS transaction logic must validate prediction/production
-- snapshots against their source rows and initialize remaining leftovers to
-- produced - units_sold. Subsequent allocations update that balance under locks.
-- Revenue must equal transaction quantity * unit-price snapshot totals.
-- Ingredient cost comes from exact FEFO movements and batch MYR/kg snapshots,
-- including ingredients used for unsold units; round once to currency precision.
-- Commit inventory, production, sales, results and simulation history atomically.
-- These cross-table checks are not implemented by this table migration.
-- Reports display NULL percentages as Not Applicable; profit may be negative.
-- Estimated demand is analytical; model training/evaluation uses units_sold.
-- Leftovers are not automatically discarded waste. Gross-profit margin is
-- calculated for reports as gross_profit / revenue * 100, or NULL at zero revenue.

COMMIT;
