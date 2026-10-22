BEGIN;

CREATE TABLE public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    notification_type text NOT NULL
        CHECK (notification_type IN (
            'LOW_STOCK', 'EXPIRING_BATCH', 'EXPIRED_BATCH', 'LOW_CONFIDENCE',
            'LOST_SALES', 'EXCESSIVE_LEFTOVER', 'DONATION_STATUS',
            'MODEL_OPERATION_FAILURE', 'EXTERNAL_SERVICE_FAILURE',
            'SYSTEM_FAILURE', 'ADMINISTRATIVE_EVENT'
        )),
    severity text NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    title text NOT NULL CHECK (length(trim(title)) > 0),
    message text NOT NULL CHECK (length(trim(message)) > 0),
    related_entity_type text,
    related_entity_id uuid,
    is_read boolean NOT NULL DEFAULT false,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notifications_related_entity_check
        CHECK (
            (related_entity_type IS NULL AND related_entity_id IS NULL)
            OR (
                related_entity_type IS NOT NULL
                AND length(trim(related_entity_type)) > 0
                AND related_entity_id IS NOT NULL
            )
        ),
    CONSTRAINT notifications_read_state_check
        CHECK ((is_read = false) = (read_at IS NULL))
);

CREATE INDEX idx_notifications_recipient_unread
    ON public.notifications (recipient_user_id, is_read, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- One notification row belongs to one recipient; read state is personal.
-- Later Node services authorize recipients and all writes, including mark-read.
-- Related entity identifiers are navigation references, not foreign keys;
-- Node must validate the entity type and the recipient's access to it.
-- Recipient-only authenticated SELECT policy and Realtime configuration are
-- a later security step; this migration intentionally enables no client access.
-- Push preferences, recipient-owned FCM tokens and delivery attempts will be
-- stored in separate tables. This migration sends no notifications.

COMMIT;
