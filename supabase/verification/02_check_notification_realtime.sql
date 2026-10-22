-- Read-only configuration check, not an authenticated isolation test.
SELECT
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public' AND tablename = 'notifications'
    ) THEN 'PASS' ELSE 'MISSING' END AS notification_publication,
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication
        WHERE pubname = 'supabase_realtime' AND pubinsert AND pubupdate
    ) THEN 'PASS' ELSE 'CHECK CONFIGURATION' END AS insert_update_events,
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'notifications'
          AND policyname = 'recipient_notification_realtime' AND cmd = 'SELECT'
    ) THEN 'PASS' ELSE 'MISSING' END AS recipient_policy;