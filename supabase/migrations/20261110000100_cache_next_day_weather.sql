BEGIN;

-- Called only by Node's authenticated manager prediction workflow. Existing
-- weather is immutable so a prediction never changes meaning after generation.
CREATE FUNCTION public.cache_next_day_weather(
    p_actor_user_id uuid, p_weather_date date, p_condition text,
    p_temp_high_c numeric, p_temp_low_c numeric, p_humidity_pct numeric
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE cached_id uuid;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'BAKERY_MANAGER'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active Bakery Manager required.';
    END IF;
    IF p_weather_date IS NULL OR p_condition NOT IN
       ('CLEAR', 'CLOUDY', 'RAIN', 'STORM', 'OTHER')
       OR p_temp_low_c IS NULL OR p_temp_high_c IS NULL
       OR p_temp_low_c > p_temp_high_c OR p_temp_low_c < -100
       OR p_temp_high_c > 100 OR p_humidity_pct NOT BETWEEN 0 AND 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid forecast.';
    END IF;
    INSERT INTO public.weather_records (
        weather_date, condition, temp_high_c, temp_low_c, humidity_pct
    ) VALUES (
        p_weather_date, p_condition, p_temp_high_c,
        p_temp_low_c, p_humidity_pct
    ) ON CONFLICT (weather_date) DO NOTHING
    RETURNING id INTO cached_id;
    IF cached_id IS NOT NULL THEN
        INSERT INTO public.system_logs (actor_user_id, event_type,
            entity_type, entity_id, outcome, severity, payload)
        VALUES (p_actor_user_id, 'WEATHER_FORECAST_CACHED',
            'weather_records', cached_id, 'SUCCESS', 'INFO',
            jsonb_build_object('date', p_weather_date,
                'provider', 'OPENWEATHER_5_DAY_3_HOUR'));
    ELSE
        SELECT id INTO cached_id FROM public.weather_records
        WHERE weather_date = p_weather_date;
    END IF;
    RETURN cached_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cache_next_day_weather(
    uuid, date, text, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cache_next_day_weather(
    uuid, date, text, numeric, numeric, numeric) TO service_role;

COMMIT;
