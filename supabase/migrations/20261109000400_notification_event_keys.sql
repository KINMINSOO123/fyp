BEGIN;

-- Deduplicate one business event independently for each intended recipient.
-- NULL remains available for older notification rows.
ALTER TABLE public.notifications
    ADD COLUMN event_key text
    CHECK (event_key IS NULL OR length(trim(event_key)) > 0);
ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_recipient_type_event_key_unique
    UNIQUE (recipient_user_id, notification_type, event_key);

COMMIT;
