BEGIN;

CREATE TABLE public.daily_production (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    production_date date NOT NULL,
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    production_decision_id uuid NOT NULL UNIQUE,
    recommended_qty integer NOT NULL CHECK (recommended_qty >= 0),
    actual_produced integer NOT NULL CHECK (actual_produced >= 0),
    adjustment_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT daily_production_date_category_key
        UNIQUE (production_date, bread_category_id),
    CONSTRAINT daily_production_id_date_category_key
        UNIQUE (id, production_date, bread_category_id),
    CONSTRAINT daily_production_decision_context_fk
        FOREIGN KEY (production_decision_id, production_date, bread_category_id)
        REFERENCES public.production_decisions (id, target_date, bread_category_id)
        ON DELETE RESTRICT,
    CONSTRAINT daily_production_adjustment_reason_check
        CHECK (
            actual_produced = recommended_qty
            OR (
                adjustment_reason IS NOT NULL
                AND length(trim(adjustment_reason)) > 0
            )
        )
);

ALTER TABLE public.daily_production ENABLE ROW LEVEL SECURITY;

-- Later Node-owned POS transaction logic must lock the confirmed decision,
-- copy recommended_qty from recommended_production and actual_produced from
-- final_selected_qty, and preserve the manager's applicable adjustment reason.
-- This is not a separate path for unconfirmed production overrides.
-- Revalidate shared ingredients and deduct eligible FEFO batches exactly once.
-- Commit production, batch/snapshot changes, movements, sales, daily results
-- and validated simulation history together; any failure rolls back all.
-- Unique links help prevent duplicates but do not implement this workflow.

COMMIT;
