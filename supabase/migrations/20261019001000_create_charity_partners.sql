BEGIN;

CREATE TABLE public.charity_partners (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(trim(name)) > 0),
    contact_info text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_charity_partners_active_name
    ON public.charity_partners (lower(trim(name)))
    WHERE is_active = true;

CREATE INDEX idx_charity_partners_active
    ON public.charity_partners (is_active, name);

CREATE TRIGGER charity_partners_set_updated_at
    BEFORE UPDATE ON public.charity_partners
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.charity_partners ENABLE ROW LEVEL SECURITY;

-- Later Node services must restrict partner maintenance to ACTIVE System
-- Administrators and validate an active partner when allocating a donation.
-- Deactivate partners instead of deleting donation history.
-- Partner registration does not automatically allocate or send donations.

COMMIT;
