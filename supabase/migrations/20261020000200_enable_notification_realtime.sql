-- Run after 20261020000100_notification_recipient_read_policy.sql.
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class AS relation
        JOIN pg_catalog.pg_namespace AS schema ON schema.oid = relation.relnamespace
        WHERE schema.nspname = 'public' AND relation.relname = 'notifications'
          AND relation.relrowsecurity
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'notifications'
          AND policyname = 'recipient_notification_realtime' AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'Apply notification recipient read policy and enable RLS first';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        RAISE EXCEPTION 'supabase_realtime publication is missing; inspect project Realtime setup';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication
        WHERE pubname = 'supabase_realtime' AND pubinsert AND pubupdate
    ) THEN
        RAISE EXCEPTION 'Realtime publication must support INSERT and UPDATE; review its configuration';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
END;
$$;

-- Existing publication tables and event settings are preserved.
-- Later Flutter subscriptions listen to INSERT/UPDATE for the authenticated
-- recipient, with RLS as the access boundary. Do not subscribe to DELETE events.
-- Account/preference changes require subscription and visible-state handling;
-- this SQL does not implement the app or prove recipient isolation.
-- notification_deliveries remains for FCM attempts, not Realtime events.

COMMIT;
