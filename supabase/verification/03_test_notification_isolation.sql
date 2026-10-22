-- Run this WHOLE file as postgres in Supabase SQL Editor.
-- Requires two existing profiles. No temporary tables or Auth accounts are created.
-- All fixture rows and profile/preference changes are rolled back.
-- Tests database RLS/grants only, not JWT verification or live Realtime delivery.
BEGIN;

DO $test$
DECLARE
    users uuid[];
    user_a uuid;
    user_b uuid;
    a_enabled uuid := gen_random_uuid();
    a_disabled uuid := gen_random_uuid();
    a_default uuid := gen_random_uuid();
    b_enabled uuid := gen_random_uuid();
    visible bigint;
    affected bigint;
    passed boolean;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Run the whole script using the postgres database role';
    END IF;
    SELECT array_agg(user_id ORDER BY role, user_id) INTO users FROM public.user_profiles;
    IF COALESCE(cardinality(users), 0) < 2 THEN
        RAISE EXCEPTION 'Two existing user_profiles are required; no tests ran';
    END IF;
    user_a := users[1];
    user_b := users[2];

    UPDATE public.user_profiles SET account_status = 'ACTIVE'
    WHERE user_id IN (user_a, user_b);
    INSERT INTO public.notification_preferences
        (user_id, notification_type, in_app_enabled, push_enabled)
    VALUES (user_a, 'LOW_STOCK', true, false),
           (user_a, 'LOW_CONFIDENCE', false, false),
           (user_b, 'LOW_STOCK', true, false)
    ON CONFLICT (user_id, notification_type) DO UPDATE
    SET in_app_enabled = EXCLUDED.in_app_enabled, push_enabled = false;
    DELETE FROM public.notification_preferences
    WHERE user_id = user_a AND notification_type = 'SYSTEM_FAILURE';
    INSERT INTO public.notifications
        (id, recipient_user_id, notification_type, severity, title, message)
    VALUES (a_enabled, user_a, 'LOW_STOCK', 'INFO', 'Rollback test', 'Enabled A'),
           (a_disabled, user_a, 'LOW_CONFIDENCE', 'INFO', 'Rollback test', 'Disabled A'),
           (a_default, user_a, 'SYSTEM_FAILURE', 'INFO', 'Rollback test', 'Default A'),
           (b_enabled, user_b, 'LOW_STOCK', 'INFO', 'Rollback test', 'Enabled B');

    PERFORM set_config('request.jwt.claim.sub', user_a::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF current_user <> 'authenticated' THEN RAISE EXCEPTION 'Role switch failed'; END IF;
    SELECT count(*) INTO visible FROM public.notifications WHERE id = a_enabled;
    IF visible <> 1 THEN RAISE EXCEPTION 'FAIL 1: A own enabled read'; END IF;
    SELECT count(*) INTO visible FROM public.notifications WHERE id = b_enabled;
    IF visible <> 0 THEN RAISE EXCEPTION 'FAIL 2: A cannot read B'; END IF;
    SELECT count(*) INTO visible FROM public.notifications WHERE id = a_disabled;
    IF visible <> 0 THEN RAISE EXCEPTION 'FAIL 3: Disabled preference hides alert'; END IF;
    SELECT count(*) INTO visible FROM public.notifications WHERE id = a_default;
    IF visible <> 1 THEN RAISE EXCEPTION 'FAIL 4: Missing preference allows in-app default'; END IF;
    passed := false;
    BEGIN
        INSERT INTO public.notifications (recipient_user_id, notification_type, severity, title, message) VALUES (user_a, 'LOW_STOCK', 'INFO', 'Forbidden', 'Forbidden');
        GET DIAGNOSTICS affected = ROW_COUNT;
        passed := affected = 0;
        RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'Undo write probe';
    EXCEPTION
        WHEN insufficient_privilege THEN passed := true;
        WHEN SQLSTATE 'ZX001' THEN NULL;
    END;
    IF NOT passed THEN RAISE EXCEPTION 'FAIL 5: authenticated INSERT allowed'; END IF;
    passed := false;
    BEGIN
        UPDATE public.notifications SET is_read = true, read_at = now() WHERE id = a_enabled;
        GET DIAGNOSTICS affected = ROW_COUNT;
        passed := affected = 0;
        RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'Undo write probe';
    EXCEPTION
        WHEN insufficient_privilege THEN passed := true;
        WHEN SQLSTATE 'ZX001' THEN NULL;
    END;
    IF NOT passed THEN RAISE EXCEPTION 'FAIL 6: authenticated UPDATE allowed'; END IF;
    passed := false;
    BEGIN
        DELETE FROM public.notifications WHERE id = a_enabled;
        GET DIAGNOSTICS affected = ROW_COUNT;
        passed := affected = 0;
        RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'Undo write probe';
    EXCEPTION
        WHEN insufficient_privilege THEN passed := true;
        WHEN SQLSTATE 'ZX001' THEN NULL;
    END;
    IF NOT passed THEN RAISE EXCEPTION 'FAIL 7: authenticated DELETE allowed'; END IF;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub', user_b::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', user_b, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO visible FROM public.notifications WHERE id = b_enabled;
    IF visible <> 1 THEN RAISE EXCEPTION 'FAIL 8: B cannot read own notification'; END IF;
    SELECT count(*) INTO visible FROM public.notifications WHERE id = a_enabled;
    IF visible <> 0 THEN RAISE EXCEPTION 'FAIL 8: B can read A notification'; END IF;

    EXECUTE 'RESET ROLE';
    UPDATE public.user_profiles SET account_status = 'INACTIVE' WHERE user_id = user_a;
    PERFORM set_config('request.jwt.claim.sub', user_a::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO visible FROM public.notifications WHERE id = a_enabled;
    IF visible <> 0 THEN RAISE EXCEPTION 'FAIL 9: inactive user can read notification'; END IF;

    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    EXECUTE 'SET LOCAL ROLE anon';
    passed := false;
    BEGIN
        SELECT count(*) INTO visible FROM public.notifications WHERE id IN (a_enabled, b_enabled);
        passed := visible = 0;
    EXCEPTION WHEN insufficient_privilege THEN passed := true;
    END;
    IF NOT passed THEN RAISE EXCEPTION 'FAIL 10: anonymous notification read allowed'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: all 10 notification permission checks completed';
END;
$test$;

-- A failed assertion aborts the transaction, so this SELECT cannot succeed on failure.
SELECT 'PASS: all 10 notification permission checks completed' AS test_result;
ROLLBACK;
