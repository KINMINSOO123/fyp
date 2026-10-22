BEGIN;

CREATE TABLE public.model_evaluations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    model_version_id uuid NOT NULL
        REFERENCES public.ml_model_versions(id) ON DELETE RESTRICT,
    holdout_start date NOT NULL,
    holdout_end date NOT NULL,
    holdout_manifest jsonb NOT NULL
        CHECK (jsonb_typeof(holdout_manifest) = 'object'),
    holdout_fingerprint text NOT NULL
        CHECK (length(trim(holdout_fingerprint)) > 0),
    data_origins text[] NOT NULL,
    evaluation_label text NOT NULL
        CHECK (evaluation_label IN (
            'ACTUAL_ONLY', 'IMPORTED_HISTORICAL_ONLY',
            'SIMULATION_BASED', 'MIXED_NON_SIMULATION'
        )),
    mae numeric(14,4) NOT NULL CHECK (mae >= 0 AND mae <> 'NaN'::numeric),
    rmse numeric(14,4) NOT NULL
        CHECK (rmse >= 0 AND rmse >= mae AND rmse <> 'NaN'::numeric),
    mape numeric(14,4)
        CHECK (mape IS NULL OR (mape >= 0 AND mape <> 'NaN'::numeric)),
    r_squared numeric(14,6)
        CHECK (r_squared IS NULL OR r_squared <= 1),
    sample_count integer NOT NULL CHECK (sample_count > 0),
    mape_sample_count integer NOT NULL
        CHECK (mape_sample_count >= 0 AND mape_sample_count <= sample_count),
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT model_evaluations_holdout_dates_check
        CHECK (holdout_start <= holdout_end),
    -- Enumerating the seven valid arrays also rejects empty, duplicate,
    -- unsorted, multidimensional and NULL-containing origin arrays.
    CONSTRAINT model_evaluations_origins_check
        CHECK (data_origins IN (
            ARRAY['ACTUAL_TRANSACTION']::text[],
            ARRAY['IMPORTED_HISTORICAL']::text[],
            ARRAY['SIMULATION_GENERATED']::text[],
            ARRAY['ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL']::text[],
            ARRAY['ACTUAL_TRANSACTION', 'SIMULATION_GENERATED']::text[],
            ARRAY['IMPORTED_HISTORICAL', 'SIMULATION_GENERATED']::text[],
            ARRAY['ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL', 'SIMULATION_GENERATED']::text[]
        )),
    CONSTRAINT model_evaluations_origin_label_check
        CHECK (evaluation_label = CASE
            WHEN 'SIMULATION_GENERATED' = ANY(data_origins)
                THEN 'SIMULATION_BASED'
            WHEN data_origins = ARRAY['ACTUAL_TRANSACTION']::text[]
                THEN 'ACTUAL_ONLY'
            WHEN data_origins = ARRAY['IMPORTED_HISTORICAL']::text[]
                THEN 'IMPORTED_HISTORICAL_ONLY'
            ELSE 'MIXED_NON_SIMULATION'
        END),
    CONSTRAINT model_evaluations_mape_availability_check
        CHECK ((mape IS NULL) = (mape_sample_count = 0))
);

CREATE INDEX idx_model_evaluations_version_time
    ON public.model_evaluations (model_version_id, evaluated_at DESC);

ALTER TABLE public.model_evaluations ENABLE ROW LEVEL SECURITY;

-- The later Node evaluation service must verify the manifest contents,
-- fingerprint, observation origins/counts and metric calculations. Test data
-- must be chronologically later and unused for fitting/parameter selection.
-- Active and candidate models must be compared on the same test dataset.
-- Zero actuals are excluded only from MAPE; undefined MAPE/R-squared are NULL.
-- Activation and higher-MAE rejection are separate lifecycle operations;
-- inserting an evaluation here does not activate a model.

COMMIT;
