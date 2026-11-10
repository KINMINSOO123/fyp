BEGIN;

-- Server-only RPCs. Each setting change and its audit event commit together.
CREATE FUNCTION public.update_bakery_settings_with_audit(
    p_actor_user_id uuid,
    p_name text,
    p_location_type text,
    p_opens_at time,
    p_closes_at time,
    p_timezone text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    old_row public.bakery_settings%ROWTYPE;
    new_row public.bakery_settings%ROWTYPE;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
    END IF;
    IF p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 120
       OR p_location_type IS NULL OR length(trim(p_location_type)) NOT BETWEEN 1 AND 120
       OR p_opens_at IS NULL OR p_closes_at IS NULL OR p_opens_at >= p_closes_at
       OR p_timezone IS NULL OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid bakery settings.';
    END IF;

    SELECT * INTO STRICT old_row FROM public.bakery_settings
    WHERE singleton_guard = true FOR UPDATE;
    UPDATE public.bakery_settings
    SET name = trim(p_name), location_type = trim(p_location_type),
        opens_at = p_opens_at, closes_at = p_closes_at,
        timezone = p_timezone
    WHERE id = old_row.id
    RETURNING * INTO new_row;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'BAKERY_SETTINGS_UPDATED', 'bakery_settings', new_row.id,
        'SUCCESS', 'INFO',
        jsonb_build_object(
            'previous', jsonb_build_object('name', old_row.name,
                'locationType', old_row.location_type,
                'opensAt', left(old_row.opens_at::text, 5),
                'closesAt', left(old_row.closes_at::text, 5),
                'timezone', old_row.timezone),
            'current', jsonb_build_object('name', new_row.name,
                'locationType', new_row.location_type,
                'opensAt', left(new_row.opens_at::text, 5),
                'closesAt', left(new_row.closes_at::text, 5),
                'timezone', new_row.timezone)
        )
    );
    RETURN jsonb_build_object(
        'id', new_row.id, 'name', new_row.name,
        'locationType', new_row.location_type,
        'opensAt', left(new_row.opens_at::text, 5),
        'closesAt', left(new_row.closes_at::text, 5),
        'timezone', new_row.timezone,
        'updatedAt', new_row.updated_at
    );
END;
$$;

CREATE FUNCTION public.update_admin_system_setting_with_audit(
    p_actor_user_id uuid,
    p_setting_key text,
    p_setting_value jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    old_value jsonb;
    saved public.system_settings%ROWTYPE;
    required_type text;
    required_description text;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id
      AND role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE'
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
    END IF;

    IF p_setting_key = 'prediction.low_confidence_threshold' THEN
        required_type := 'NUMERIC';
        required_description := 'Model confidence below this percentage is labelled Low Confidence.';
        IF jsonb_typeof(p_setting_value) IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid confidence threshold.';
        END IF;
        IF (p_setting_value #>> '{}')::numeric < 0
           OR (p_setting_value #>> '{}')::numeric > 100 THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid confidence threshold.';
        END IF;
    ELSIF p_setting_key = 'prediction.context_rules' THEN
        required_type := 'JSON';
        required_description := 'Configured prediction factors and explicitly labelled context fallbacks.';
        IF jsonb_typeof(p_setting_value) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid prediction context rules.';
        END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Setting key is not editable.';
    END IF;

    SELECT setting_value INTO old_value FROM public.system_settings
    WHERE setting_key = p_setting_key FOR UPDATE;
    INSERT INTO public.system_settings (
        setting_key, setting_value, data_type, description, updated_by
    ) VALUES (
        p_setting_key, p_setting_value, required_type,
        required_description, p_actor_user_id
    )
    ON CONFLICT (setting_key) DO UPDATE
    SET setting_value = EXCLUDED.setting_value,
        data_type = EXCLUDED.data_type,
        description = EXCLUDED.description,
        updated_by = EXCLUDED.updated_by
    RETURNING * INTO saved;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'SYSTEM_SETTING_UPDATED', 'system_settings', saved.id,
        'SUCCESS', 'INFO',
        jsonb_build_object('settingKey', p_setting_key,
            'previousValue', old_value, 'currentValue', p_setting_value)
    );
    RETURN jsonb_build_object(
        'key', saved.setting_key, 'value', saved.setting_value,
        'dataType', saved.data_type, 'description', saved.description,
        'updatedBy', saved.updated_by, 'updatedAt', saved.updated_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_bakery_settings_with_audit(
    uuid, text, text, time, time, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_bakery_settings_with_audit(
    uuid, text, text, time, time, text) TO service_role;
REVOKE ALL ON FUNCTION public.update_admin_system_setting_with_audit(
    uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_admin_system_setting_with_audit(
    uuid, text, jsonb) TO service_role;

COMMIT;
