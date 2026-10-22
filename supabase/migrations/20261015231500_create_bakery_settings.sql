BEGIN;

CREATE TABLE public.bakery_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    singleton_guard boolean NOT NULL DEFAULT true
        UNIQUE
        CHECK (singleton_guard = true),

    name text NOT NULL
        CHECK (length(trim(name)) > 0),

    location_type text NOT NULL
        CHECK (length(trim(location_type)) > 0),

    opens_at time NOT NULL,

    closes_at time NOT NULL,

    timezone text NOT NULL DEFAULT 'Asia/Kuala_Lumpur'
        CHECK (length(trim(timezone)) > 0),

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),

    CHECK (opens_at < closes_at)
);

CREATE TRIGGER set_bakery_settings_updated_at
BEFORE UPDATE ON public.bakery_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.bakery_settings
ENABLE ROW LEVEL SECURITY;

-- Example bakery configuration: edit these values before running.
INSERT INTO public.bakery_settings (
    name,
    location_type,
    opens_at,
    closes_at
)
VALUES (
    'Smart Bakery',
    'Residential neighbourhood',
    '06:00',
    '18:00'
);

COMMIT;