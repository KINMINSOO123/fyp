BEGIN;

CREATE TABLE public.donations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    daily_result_id uuid NOT NULL
        REFERENCES public.daily_results(id) ON DELETE RESTRICT,
    charity_partner_id uuid NOT NULL
        REFERENCES public.charity_partners(id) ON DELETE RESTRICT,
    donation_date date NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'COLLECTED', 'COMPLETED', 'CANCELLED')),
    confirmed_by uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_donations_result_date
    ON public.donations (daily_result_id, donation_date);
CREATE INDEX idx_donations_partner_status
    ON public.donations (charity_partner_id, status);

CREATE TRIGGER donations_set_updated_at
    BEFORE UPDATE ON public.donations
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

-- Bread category is derived through daily_result_id.
-- Later Node allocation logic must authorize an ACTIVE Bakery Manager, derive
-- confirmed_by server-side, verify an active charity and donation_date >= the
-- result date, and lock the result while checking remaining unallocated units.
-- Insert the allocation and reduce remaining_unallocated_leftover atomically.
-- Maintain leftover = donated + wasted + remaining_unallocated; concurrent
-- requests must not allocate the same units twice. This table alone does not
-- implement these cross-row checks or automatically change leftover balances.
-- Status updates require manager authorization, audit and recipient events.
-- PENDING -> COLLECTED -> COMPLETED is the planned normal workflow.
-- CANCELLED is a recognized value, but cancellation/reallocation policy remains
-- unresolved; do not enable cancellation or silently release units yet.

COMMIT;
