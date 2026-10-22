-- Run as the database administrator in Supabase SQL Editor.
BEGIN;

CREATE SCHEMA IF NOT EXISTS private;

CREATE FUNCTION private.realtime_notification_allowed(requested_type text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.user_profiles AS profile
        LEFT JOIN public.notification_preferences AS preference
            ON preference.user_id = profile.user_id
            AND preference.notification_type = requested_type
        WHERE profile.user_id = (SELECT auth.uid())
          AND profile.account_status = 'ACTIVE'
          AND COALESCE(preference.in_app_enabled, true)
    );
$$;

ALTER FUNCTION private.realtime_notification_allowed(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.realtime_notification_allowed(text)
    FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.realtime_notification_allowed(text)
    TO authenticated;

-- Fail rather than silently combine this policy with unknown existing policies.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'notifications'
    ) THEN
        RAISE EXCEPTION 'notifications already has policies; review them before applying this migration';
    END IF;
END;
$$;

REVOKE ALL ON public.notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notifications TO authenticated;

CREATE POLICY recipient_notification_realtime
ON public.notifications FOR SELECT TO authenticated
USING (
    recipient_user_id = (SELECT auth.uid())
    AND private.realtime_notification_allowed(notification_type)
);

-- Keep private outside the Data API exposed schemas. The helper returns only
-- the current user's eligibility; it takes no user ID and grants no table reads.
-- No client write policy: mark-read and all other writes must use Node.
-- Missing preferences default to in-app enabled, never to push enabled.
-- Publication/subscription configuration and real-user isolation tests follow
-- separately. This migration does not yet enable Realtime publication.

COMMIT;
