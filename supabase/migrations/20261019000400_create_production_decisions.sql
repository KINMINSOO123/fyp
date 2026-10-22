BEGIN;

CREATE TABLE public.production_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_date date NOT NULL,
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    prediction_id uuid NOT NULL UNIQUE,
    predicted_units_sold integer NOT NULL CHECK (predicted_units_sold >= 0),
    recommended_production integer NOT NULL CHECK (recommended_production >= 0),
    max_producible integer NOT NULL CHECK (max_producible >= 0),
    final_selected_qty integer NOT NULL
        CHECK (final_selected_qty >= 0 AND final_selected_qty <= max_producible),
    selected_option text NOT NULL
        CHECK (selected_option IN ('ACCEPT_RECOMMENDATION', 'REDUCE', 'MANUAL_OVERRIDE')),
    decision_reason text,
    confirmed_by uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT production_decisions_date_category_key
        UNIQUE (target_date, bread_category_id),
    CONSTRAINT production_decisions_id_date_category_key
        UNIQUE (id, target_date, bread_category_id),
    CONSTRAINT production_decisions_prediction_context_fk
        FOREIGN KEY (prediction_id, target_date, bread_category_id)
        REFERENCES public.daily_predictions (id, target_date, bread_category_id)
        ON DELETE RESTRICT,
    CONSTRAINT production_decisions_option_check
        CHECK (
            (
                selected_option = 'ACCEPT_RECOMMENDATION'
                AND final_selected_qty = recommended_production
                AND decision_reason IS NULL
            )
            OR
            (
                selected_option = 'REDUCE'
                AND final_selected_qty < recommended_production
                AND decision_reason IS NOT NULL
                AND length(trim(decision_reason)) > 0
            )
            OR
            (
                selected_option = 'MANUAL_OVERRIDE'
                AND decision_reason IS NOT NULL
                AND length(trim(decision_reason)) > 0
            )
        )
);

CREATE INDEX idx_decisions_confirmed_by
    ON public.production_decisions (confirmed_by, confirmed_at DESC);

CREATE TRIGGER production_decisions_set_updated_at
    BEFORE UPDATE ON public.production_decisions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.production_decisions ENABLE ROW LEVEL SECURITY;

-- Later Node services must authorize an ACTIVE Bakery Manager, derive actor
-- and feasibility values server-side, and preserve the prediction snapshot.
-- Confirm/revise under locks: validate combined outstanding recipe requirements,
-- replace the old quantity on revision and recalculate affected recommendations.
-- Reject changes to processed decisions; confirmation never deducts inventory.
-- These cross-row workflow checks are not implemented by this table migration.

COMMIT;
