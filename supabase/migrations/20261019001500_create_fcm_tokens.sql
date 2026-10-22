BEGIN;

CREATE TABLE public.fcm_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    token text NOT NULL UNIQUE CHECK (length(trim(token)) > 0),
    device_info text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_fcm_tokens_user_active
    ON public.fcm_tokens (user_id, is_active);

CREATE TRIGGER fcm_tokens_set_updated_at
    BEFORE UPDATE ON public.fcm_tokens
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Later Node services register/unregister devices for the validated ACTIVE
-- user, deriving ownership from authentication rather than client user_id.
-- A user may have multiple device registrations. Token rotation deactivates
-- the old registration while preserving references from delivery history.
-- Logout/account-switch handling must prevent push to a previous user's session.
-- Push dispatch requires an active recipient, explicit per-type push preference,
-- OS permission and a valid active token belonging to that recipient.
-- Provider credentials are not stored here; token is a device registration token.
-- This migration neither registers devices nor sends notifications.

COMMIT;
