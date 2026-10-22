BEGIN;

CREATE TABLE public.daily_predictions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_date date NOT NULL,
    bread_category_id uuid NOT NULL
        REFERENCES public.bread_categories(id) ON DELETE RESTRICT,
    predicted_units_sold integer NOT NULL CHECK (predicted_units_sold >= 0),
    -- Preserve calculation precision; round only for display.
    confidence numeric,
    prediction_mode text NOT NULL
        CHECK (prediction_mode IN ('MODEL', 'COLD_START')),
    model_version_id uuid
        REFERENCES public.ml_model_versions(id) ON DELETE RESTRICT,
    weather_record_id uuid
        REFERENCES public.weather_records(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT daily_predictions_date_category_key
        UNIQUE (target_date, bread_category_id),
    -- Supports later composite foreign keys that enforce date/category matching.
    CONSTRAINT daily_predictions_id_date_category_key
        UNIQUE (id, target_date, bread_category_id),
    CONSTRAINT daily_predictions_mode_confidence_check
        CHECK (
            (
                prediction_mode = 'MODEL'
                AND model_version_id IS NOT NULL
                AND confidence IS NOT NULL
                AND confidence BETWEEN 0 AND 100
            )
            OR
            (
                prediction_mode = 'COLD_START'
                AND model_version_id IS NULL
                AND confidence IS NULL
            )
        )
);

CREATE INDEX idx_predictions_model
    ON public.daily_predictions (model_version_id);

ALTER TABLE public.daily_predictions ENABLE ROW LEVEL SECURITY;

-- Later Node/ML services must validate generation permission, the 30 distinct
-- validated-day threshold and a valid active Random Forest for this category.
-- Model references remain valid historical references after deactivation.
-- ConfidenceService calculates tree agreement; cold start has no percentage.
-- Context is already applied to the stored prediction, not reapplied in POS.
-- This migration stores predictions; it does not generate them or implement
-- those service-level checks.

COMMIT;
