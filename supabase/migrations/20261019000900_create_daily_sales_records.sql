BEGIN;

CREATE TABLE public.daily_sales_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_date date NOT NULL,
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    units_sold integer NOT NULL CHECK (units_sold >= 0),
    data_origin text NOT NULL
        CHECK (data_origin IN (
            'ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL', 'SIMULATION_GENERATED'
        )),
    is_validated boolean NOT NULL DEFAULT false,
    source_daily_result_id uuid,
    external_source_reference text,
    validation_notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT daily_sales_records_date_category_origin_key
        UNIQUE (sales_date, bread_category_id, data_origin),
    CONSTRAINT daily_sales_records_result_context_fk
        FOREIGN KEY (source_daily_result_id, sales_date, bread_category_id)
        REFERENCES public.daily_results (id, result_date, bread_category_id)
        ON DELETE RESTRICT,
    CONSTRAINT daily_sales_records_origin_source_check
        CHECK (
            (
                data_origin = 'SIMULATION_GENERATED'
                AND source_daily_result_id IS NOT NULL
                AND external_source_reference IS NULL
                AND is_validated = true
            )
            OR
            (
                data_origin IN ('ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL')
                AND source_daily_result_id IS NULL
                AND external_source_reference IS NOT NULL
                AND length(trim(external_source_reference)) > 0
            )
        )
);

CREATE INDEX idx_daily_sales_history
    ON public.daily_sales_records (bread_category_id, sales_date, data_origin);

CREATE UNIQUE INDEX idx_daily_sales_source_result
    ON public.daily_sales_records (source_daily_result_id)
    WHERE data_origin = 'SIMULATION_GENERATED';

CREATE UNIQUE INDEX idx_daily_sales_external_source
    ON public.daily_sales_records (data_origin, external_source_reference)
    WHERE data_origin IN ('ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL');

ALTER TABLE public.daily_sales_records ENABLE ROW LEVEL SECURITY;

-- Later Node POS logic must copy units_sold from the linked daily result and
-- insert one validated simulation observation per category in the same atomic
-- transaction as inventory, production, sales and results. These cross-table
-- value/completeness checks are not implemented by this table migration.
-- Actual/imported source references identify individual category/day records,
-- not just a shared import file. Backend validation controls is_validated.
-- For training/evaluation, choose one validated record per category/day in
-- ACTUAL_TRANSACTION > IMPORTED_HISTORICAL > SIMULATION_GENERATED priority.
-- Count those distinct days for the 30-day threshold; never add origins together.
-- The learning target is units_sold, not estimated demand.

COMMIT;
