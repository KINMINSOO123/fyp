BEGIN;

CREATE TABLE public.notification_preferences (
    user_id uuid NOT NULL
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    notification_type text NOT NULL
        CHECK (notification_type IN (
            'LOW_STOCK', 'EXPIRING_BATCH', 'EXPIRED_BATCH', 'LOW_CONFIDENCE',
            'LOST_SALES', 'EXCESSIVE_LEFTOVER', 'DONATION_STATUS',
            'MODEL_OPERATION_FAILURE', 'EXTERNAL_SERVICE_FAILURE',
            'SYSTEM_FAILURE', 'ADMINISTRATIVE_EVENT'
        )),
    in_app_enabled boolean NOT NULL DEFAULT true,
    push_enabled boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, notification_type)
);

CREATE TRIGGER notification_preferences_set_updated_at
    BEFORE UPDATE ON public.notification_preferences
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- The composite primary key also supports preference lookups for a user.
-- Later Node services allow ACTIVE users of either role to manage only their
-- own preferences, deriving user_id from the validated identity.
-- Missing preference rows do not authorize push. Sending requires explicit
-- push opt-in, OS permission and a valid active token owned by the recipient.
-- In-app visibility must honor the recipient's in_app_enabled preference.
-- This migration creates no preference rows and sends no notifications.

COMMIT;
