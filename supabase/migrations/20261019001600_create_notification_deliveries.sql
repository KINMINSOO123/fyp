BEGIN;

CREATE TABLE public.notification_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id uuid NOT NULL
        REFERENCES public.notifications(id) ON DELETE RESTRICT,
    fcm_token_id uuid
        REFERENCES public.fcm_tokens(id) ON DELETE RESTRICT,
    attempt_number integer NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    push_status text NOT NULL DEFAULT 'PENDING'
        CHECK (push_status IN ('PENDING', 'SUBMITTED', 'DELIVERED', 'FAILED', 'SKIPPED')),
    provider_message_id text,
    attempted_at timestamptz,
    delivered_at timestamptz,
    failure_reason text,
    skip_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notification_deliveries_time_check
        CHECK (delivered_at IS NULL OR attempted_at IS NULL OR delivered_at >= attempted_at),
    CONSTRAINT notification_deliveries_status_fields_check
        CHECK (
            (push_status = 'PENDING'
                AND fcm_token_id IS NOT NULL
                AND attempted_at IS NULL AND delivered_at IS NULL
                AND provider_message_id IS NULL
                AND failure_reason IS NULL AND skip_reason IS NULL)
            OR
            (push_status = 'SUBMITTED'
                AND fcm_token_id IS NOT NULL AND attempted_at IS NOT NULL
                AND provider_message_id IS NOT NULL
                AND delivered_at IS NULL
                AND failure_reason IS NULL AND skip_reason IS NULL)
            OR
            (push_status = 'DELIVERED'
                AND fcm_token_id IS NOT NULL AND attempted_at IS NOT NULL
                AND provider_message_id IS NOT NULL AND delivered_at IS NOT NULL
                AND failure_reason IS NULL AND skip_reason IS NULL)
            OR
            (push_status = 'FAILED'
                AND fcm_token_id IS NOT NULL AND attempted_at IS NOT NULL
                AND delivered_at IS NULL
                AND failure_reason IS NOT NULL AND length(trim(failure_reason)) > 0
                AND skip_reason IS NULL)
            OR
            (push_status = 'SKIPPED'
                AND provider_message_id IS NULL
                AND attempted_at IS NULL AND delivered_at IS NULL
                AND failure_reason IS NULL
                AND skip_reason IS NOT NULL AND length(trim(skip_reason)) > 0)
        )
);

CREATE UNIQUE INDEX idx_notification_deliveries_token_attempt
    ON public.notification_deliveries (notification_id, fcm_token_id, attempt_number)
    WHERE fcm_token_id IS NOT NULL;

CREATE UNIQUE INDEX idx_notification_deliveries_tokenless
    ON public.notification_deliveries (notification_id)
    WHERE fcm_token_id IS NULL;

CREATE INDEX idx_delivery_status
    ON public.notification_deliveries (push_status, updated_at);

CREATE TRIGGER notification_deliveries_set_updated_at
    BEFORE UPDATE ON public.notification_deliveries
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

-- Later Node dispatch logic must validate that the token belongs to the
-- notification recipient and check active account/token, push preference and
-- OS permission. Foreign keys alone do not enforce recipient/token ownership.
-- Provider acceptance is SUBMITTED, not proof of delivery to the device.
-- Set DELIVERED only with supported delivery confirmation; it does not mean read.
-- Retries use separate attempt numbers. Missing tokens or disabled push can
-- produce a tokenless SKIPPED record with an explanation.
-- This migration records outcomes; it does not send push or implement retries.

COMMIT;
