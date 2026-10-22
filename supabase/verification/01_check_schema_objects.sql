-- Run in Supabase SQL Editor. Read-only: does not create or change anything.
-- Expected: 29 table rows plus one view row, all with status PASS.
-- This checks object presence, table RLS and the view's security-invoker setting.
-- It does not validate every constraint, policy, grant or application workflow.
WITH expected_tables(table_name) AS (
    VALUES
        ('user_profiles'), ('bakery_settings'), ('system_settings'),
        ('bread_categories'), ('ingredients'), ('recipes'),
        ('inventory'), ('inventory_batches'), ('inventory_log'),
        ('weather_records'), ('calendar_events'), ('daily_sales_records'),
        ('ml_model_versions'), ('model_evaluations'), ('feature_importance'),
        ('daily_predictions'), ('prediction_calendar_events'),
        ('production_decisions'), ('daily_production'), ('daily_results'),
        ('sales_transactions'), ('charity_partners'), ('donations'),
        ('waste_records'), ('notifications'), ('notification_preferences'),
        ('fcm_tokens'), ('notification_deliveries'), ('system_logs')
), checks AS (
    SELECT
        'TABLE'::text AS object_type,
        expected.table_name AS object_name,
        CASE
            WHEN relation.oid IS NULL THEN 'MISSING'
            WHEN relation.relkind NOT IN ('r', 'p') THEN 'WRONG OBJECT TYPE'
            WHEN NOT relation.relrowsecurity THEN 'RLS DISABLED'
            ELSE 'PASS'
        END AS status
    FROM expected_tables AS expected
    LEFT JOIN pg_catalog.pg_namespace AS schema
        ON schema.nspname = 'public'
    LEFT JOIN pg_catalog.pg_class AS relation
        ON relation.relnamespace = schema.oid
        AND relation.relname = expected.table_name

    UNION ALL

    SELECT
        'VIEW',
        'sales_by_timeslot',
        CASE
            WHEN relation.oid IS NULL THEN 'MISSING'
            WHEN relation.relkind <> 'v' THEN 'WRONG OBJECT TYPE'
            WHEN NOT COALESCE(
                'security_invoker=true' = ANY(relation.reloptions), false
            ) THEN 'SECURITY INVOKER NOT ENABLED'
            ELSE 'PASS'
        END
    FROM (VALUES ('sales_by_timeslot')) AS expected(view_name)
    LEFT JOIN pg_catalog.pg_namespace AS schema
        ON schema.nspname = 'public'
    LEFT JOIN pg_catalog.pg_class AS relation
        ON relation.relnamespace = schema.oid
        AND relation.relname = expected.view_name
)
SELECT object_type, object_name, status
FROM checks
ORDER BY object_type, object_name;
