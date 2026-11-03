BEGIN;

CREATE OR REPLACE FUNCTION public.create_user_profile_with_audit(
    p_actor_user_id uuid,
    p_user_id uuid,
    p_full_name text,
    p_role text,
    p_account_status text
)
RETURNS TABLE (
    user_id uuid,
    full_name text,
    role text,
    account_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Recheck permission inside the database transaction.
    IF NOT EXISTS (
        SELECT 1
        FROM public.user_profiles AS actor
        WHERE actor.user_id = p_actor_user_id
          AND actor.role = 'SYSTEM_ADMINISTRATOR'
          AND actor.account_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION
            USING ERRCODE = '42501',
                  MESSAGE = 'An active System Administrator is required.';
    END IF;

    INSERT INTO public.user_profiles (
        user_id,
        full_name,
        role,
        account_status
    )
    VALUES (
        p_user_id,
        trim(p_full_name),
        p_role,
        p_account_status
    );

    INSERT INTO public.system_logs (
        actor_user_id,
        event_type,
        entity_type,
        entity_id,
        outcome,
        severity,
        payload
    )
    VALUES (
        p_actor_user_id,
        'USER_ACCOUNT_CREATED',
        'USER_PROFILE',
        p_user_id,
        'SUCCESS',
        'INFO',
        jsonb_build_object(
            'assigned_role', p_role,
            'account_status', p_account_status
        )
    );

    RETURN QUERY
    SELECT
        profile.user_id,
        profile.full_name,
        profile.role,
        profile.account_status
    FROM public.user_profiles AS profile
    WHERE profile.user_id = p_user_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_user_profile_with_audit(
    uuid,
    uuid,
    text,
    text,
    text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.create_user_profile_with_audit(
    uuid,
    uuid,
    text,
    text,
    text
)
TO service_role;

COMMIT;