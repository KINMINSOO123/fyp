-- Run the WHOLE file as postgres. Requires one existing user_profile.
-- All fixtures roll back. Fake token/provider IDs are never sent to FCM.
-- Tests storage only, not token ownership, opt-in checks, retry execution,
-- delivery confirmation, Realtime streaming or provider integration.
BEGIN;
DO $test$
DECLARE
    recipient uuid;
    notification_id_value uuid := gen_random_uuid();
    token_id_value uuid := gen_random_uuid();
    pending_id uuid := gen_random_uuid();
    submitted_id uuid := gen_random_uuid();
    delivered_id uuid := gen_random_uuid();
    failed_id uuid := gen_random_uuid();
    skipped_id uuid := gen_random_uuid();
    rejected boolean;
BEGIN
    IF current_user <> 'postgres' THEN RAISE EXCEPTION 'Run as postgres'; END IF;
    SELECT user_id INTO recipient FROM public.user_profiles ORDER BY user_id LIMIT 1;
    IF recipient IS NULL THEN RAISE EXCEPTION 'One existing user_profile is required'; END IF;
    INSERT INTO public.notifications
        (id, recipient_user_id, notification_type, severity, title, message)
    VALUES (notification_id_value, recipient, 'LOW_STOCK', 'INFO', 'Rollback test', 'Push storage fixture');
    INSERT INTO public.fcm_tokens (id, user_id, token)
    VALUES (token_id_value, recipient, 'FAKE-ROLLBACK-ONLY-' || token_id_value::text);

    -- Checks 1-5: all five valid status shapes are accepted.
    -- Attempt numbers distinguish records; these are not actual dispatches.
    INSERT INTO public.notification_deliveries
        (id, notification_id, fcm_token_id, attempt_number, push_status,
         provider_message_id, attempted_at, delivered_at, failure_reason, skip_reason)
    VALUES
        (pending_id, notification_id_value, token_id_value, 1, 'PENDING', NULL, NULL, NULL, NULL, NULL),
        (submitted_id, notification_id_value, token_id_value, 2, 'SUBMITTED', 'fixture-submitted', now(), NULL, NULL, NULL),
        (delivered_id, notification_id_value, token_id_value, 3, 'DELIVERED', 'fixture-delivered', now(), now(), NULL, NULL),
        (failed_id, notification_id_value, token_id_value, 4, 'FAILED', NULL, now(), NULL, 'Fixture failure', NULL),
        (skipped_id, notification_id_value, NULL, 1, 'SKIPPED', NULL, NULL, NULL, NULL, 'No eligible device');

    -- Check 6: PENDING without token.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET fcm_token_id = NULL WHERE id = pending_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 6: PENDING without token accepted'; END IF;

    -- Check 7: SUBMITTED without provider ID.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET provider_message_id = NULL WHERE id = submitted_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 7: SUBMITTED without provider ID accepted'; END IF;

    -- Check 8: DELIVERED without confirmation time.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET delivered_at = NULL WHERE id = delivered_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 8: DELIVERED without confirmation time accepted'; END IF;

    -- Check 9: Delivery before attempt.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET delivered_at = attempted_at - interval '1 second' WHERE id = delivered_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 9: Delivery before attempt accepted'; END IF;

    -- Check 10: FAILED with blank explanation.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET failure_reason = '   ' WHERE id = failed_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 10: FAILED with blank explanation accepted'; END IF;

    -- Check 11: SKIPPED without explanation.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET skip_reason = NULL WHERE id = skipped_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 11: SKIPPED without explanation accepted'; END IF;

    -- Check 12: Zero attempt number.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET attempt_number = 0 WHERE id = pending_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 12: Zero attempt number accepted'; END IF;

    -- Check 13: PENDING with delivery timestamp.
    rejected := false;
    BEGIN
        UPDATE public.notification_deliveries SET delivered_at = now() WHERE id = pending_id;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 13: PENDING with delivery timestamp accepted'; END IF;

    -- Check 14: duplicate notification/device/attempt is rejected.
    rejected := false;
    BEGIN
        INSERT INTO public.notification_deliveries (notification_id, fcm_token_id, attempt_number)
        VALUES (notification_id_value, token_id_value, 1);
    EXCEPTION WHEN unique_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 14: duplicate device attempt accepted'; END IF;

    -- Check 15: only one tokenless SKIPPED record per notification.
    rejected := false;
    BEGIN
        INSERT INTO public.notification_deliveries (notification_id, push_status, skip_reason)
        VALUES (notification_id_value, 'SKIPPED', 'Duplicate skip fixture');
    EXCEPTION WHEN unique_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'FAIL 15: duplicate tokenless skip accepted'; END IF;
END;
$test$;
SELECT 'PASS: all 15 push-delivery storage checks completed' AS test_result;
ROLLBACK;
