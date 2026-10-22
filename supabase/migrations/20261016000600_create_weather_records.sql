BEGIN;

CREATE TABLE public.weather_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    weather_date date NOT NULL UNIQUE,
    condition text NOT NULL
        CHECK (condition IN ('CLEAR', 'CLOUDY', 'RAIN', 'STORM', 'OTHER')),
    temp_high_c numeric(5,2),
    temp_low_c numeric(5,2),
    humidity_pct numeric(5,2)
        CHECK (humidity_pct IS NULL OR humidity_pct BETWEEN 0 AND 100),
    fetched_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT weather_records_temperature_range_check
        CHECK (
            temp_low_c IS NULL
            OR temp_high_c IS NULL
            OR temp_low_c <= temp_high_c
        )
);

-- UNIQUE(weather_date) already provides an index for daily lookup.
-- Protected application reads and writes go through Node.
ALTER TABLE public.weather_records ENABLE ROW LEVEL SECURITY;

COMMIT;
