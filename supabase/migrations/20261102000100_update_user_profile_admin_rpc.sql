BEGIN;

CREATE OR REPLACE FUNCTION public.update_user_profile_admin_with_audit(
    p_actor_user_id uuid,
    p_target_user_id uuid,
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
DECLARE
    current_profile public.user_profiles%ROWTYPE;
    updated_profile public.user_profiles%ROWTYPE;
    remaining_active_administrators integer;
BEGIN
    -- Serialise administrative profile changes so two concurrent requests
    -- cannot both remove the final active administrator.
    LOCK TABLE public.user_profiles
        IN SHARE ROW EXCLUSIVE MODE;

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

    SELECT target.*
    INTO current_profile
    FROM public.user_profiles AS target
    WHERE target.user_id = p_target_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            USING ERRCODE = 'P0002',
                  MESSAGE = 'The target user profile does not exist.';
    END IF;

    IF p_full_name IS NOT NULL
       AND length(trim(p_full_name)) = 0 THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Full name cannot be empty.';
    END IF;

    IF p_role IS NOT NULL
       AND p_role NOT IN (
           'BAKERY_MANAGER',
           'SYSTEM_ADMINISTRATOR'
       ) THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Invalid user role.';
    END IF;

    IF p_account_status IS NOT NULL
       AND p_account_status NOT IN (
           'ACTIVE',
           'INACTIVE'
       ) THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Invalid account status.';
    END IF;

    -- Check whether this change would remove an active administrator.
    IF current_profile.role = 'SYSTEM_ADMINISTRATOR'
       AND current_profile.account_status = 'ACTIVE'
       AND (
           COALESCE(p_role, current_profile.role)
               <> 'SYSTEM_ADMINISTRATOR'
           OR
           COALESCE(
               p_account_status,
               current_profile.account_status
           ) <> 'ACTIVE'
       ) THEN

        SELECT count(*)
        INTO remaining_active_administrators
        FROM public.user_profiles AS administrator
        WHERE administrator.role = 'SYSTEM_ADMINISTRATOR'
          AND administrator.account_status = 'ACTIVE'
          AND administrator.user_id <> p_target_user_id;

        IF remaining_active_administrators = 0 THEN
            RAISE EXCEPTION
                USING ERRCODE = 'P0001',
                      MESSAGE =
                          'The final active System Administrator must be preserved.';
        END IF;
    END IF;

    UPDATE public.user_profiles AS target
    SET
        full_name = COALESCE(
            trim(p_full_name),
            target.full_name
        ),
        role = COALESCE(
            p_role,
            target.role
        ),
        account_status = COALESCE(
            p_account_status,
            target.account_status
        )
    WHERE target.user_id = p_target_user_id
    RETURNING target.*
    INTO updated_profile;

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
        'USER_ACCOUNT_UPDATED',
        'USER_PROFILE',
        p_target_user_id,
        'SUCCESS',
        'INFO',
        jsonb_build_object(
            'before',
            jsonb_build_object(
                'full_name', current_profile.full_name,
                'role', current_profile.role,
                'account_status',
                    current_profile.account_status
            ),
            'after',
            jsonb_build_object(
                'full_name', updated_profile.full_name,
                'role', updated_profile.role,
                'account_status',
                    updated_profile.account_status
            )
        )
    );

    RETURN QUERY
    SELECT
        updated_profile.user_id,
        updated_profile.full_name,
        updated_profile.role,
        updated_profile.account_status;
END;
$$;

REVOKE ALL
ON FUNCTION public.update_user_profile_admin_with_audit(
    uuid,
    uuid,
    text,
    text,
    text
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.update_user_profile_admin_with_audit(
    uuid,
    uuid,
    text,
    text,
    text
)
TO service_role;

COMMIT;