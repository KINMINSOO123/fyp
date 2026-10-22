BEGIN;

CREATE TABLE public.system_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    setting_key text NOT NULL UNIQUE
        CHECK (setting_key ~ '^[a-z][a-z0-9_.]*$'),

    setting_value jsonb NOT NULL,

    data_type text NOT NULL
        CHECK (
            data_type IN (
                'BOOLEAN',
                'INTEGER',
                'NUMERIC',
                'TEXT',
                'JSON'
            )
        ),

    description text NOT NULL
        CHECK (length(trim(description)) > 0),

    updated_by uuid NOT NULL
        REFERENCES public.user_profiles(user_id)
        ON DELETE RESTRICT,

    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT system_settings_value_type_check
    CHECK (
        CASE data_type
            WHEN 'BOOLEAN' THEN
                jsonb_typeof(setting_value) = 'boolean'

            WHEN 'INTEGER' THEN
                jsonb_typeof(setting_value) = 'number'
                AND setting_value::text ~ '^-?[0-9]+$'

            WHEN 'NUMERIC' THEN
                jsonb_typeof(setting_value) = 'number'

            WHEN 'TEXT' THEN
                jsonb_typeof(setting_value) = 'string'

            WHEN 'JSON' THEN
                jsonb_typeof(setting_value) IN ('object', 'array')

            ELSE false
        END
    )
);

CREATE TRIGGER set_system_settings_updated_at
BEFORE UPDATE ON public.system_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_system_settings_updated_at
ON public.system_settings (updated_at);

ALTER TABLE public.system_settings
ENABLE ROW LEVEL SECURITY;

COMMIT;