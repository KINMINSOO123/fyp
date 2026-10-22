BEGIN;

CREATE TABLE public.user_profiles (
    user_id uuid PRIMARY KEY
        REFERENCES auth.users(id) ON DELETE RESTRICT,

    full_name text NOT NULL
        CHECK (length(trim(full_name)) > 0),

    role text NOT NULL
        CHECK (
            role IN (
                'BAKERY_MANAGER',
                'SYSTEM_ADMINISTRATOR'
            )
        ),

    account_status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (account_status IN ('ACTIVE', 'INACTIVE')),

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Automatically update updated_at when a row changes.
CREATE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER set_user_profiles_updated_at
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- Supports filtering accounts by role and status.
CREATE INDEX idx_user_profiles_role_status
ON public.user_profiles (role, account_status);

-- Restrict direct access from application clients.
ALTER TABLE public.user_profiles
ENABLE ROW LEVEL SECURITY;

COMMIT;