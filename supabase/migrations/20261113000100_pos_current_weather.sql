BEGIN;

-- The prior independent-demand RPC still performs the complete locked POS
-- transaction. This wrapper adds validated current-weather provenance within
-- that same transaction; any failure rolls the entire operation back.
ALTER TABLE public.daily_results DROP CONSTRAINT daily_results_simulation_method_check;
ALTER TABLE public.daily_results ADD CONSTRAINT daily_results_simulation_method_check CHECK (
  (simulation_method = 'PREDICTION_SCALED_V1' AND simulation_snapshot IS NULL) OR
  (simulation_method IN ('INDEPENDENT_BASELINE_V2',
      'INDEPENDENT_CURRENT_WEATHER_V3')
    AND simulation_snapshot IS NOT NULL
    AND pg_catalog.jsonb_typeof(simulation_snapshot) = 'object')
);

CREATE FUNCTION public.complete_pos_simulation_v3(
  p_actor_user_id uuid, p_date date, p_weather_context jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  bakery_day date;
  completed jsonb;
  updated_items jsonb;
  weather_condition text;
BEGIN
  SELECT (pg_catalog.clock_timestamp() AT TIME ZONE timezone)::date INTO bakery_day
  FROM public.bakery_settings WHERE singleton_guard = true;
  IF p_date IS NULL OR bakery_day IS NULL OR p_date <> bakery_day THEN
    RAISE EXCEPTION USING ERRCODE = 'P1007',
      MESSAGE = 'Current-weather simulation is supported only for the bakery current date.';
  END IF;
  weather_condition := p_weather_context->>'condition';
  IF pg_catalog.jsonb_typeof(p_weather_context) IS DISTINCT FROM 'object'
     OR p_weather_context->>'provider' IS DISTINCT FROM 'OPENWEATHER_CURRENT'
     OR weather_condition IS NULL OR weather_condition NOT IN
        ('CLEAR', 'CLOUDY', 'RAIN', 'STORM', 'OTHER')
     OR pg_catalog.jsonb_typeof(p_weather_context->'location') IS DISTINCT FROM 'object'
     OR pg_catalog.jsonb_typeof(p_weather_context->'requestedLocation') IS DISTINCT FROM 'object'
     OR pg_catalog.jsonb_typeof(p_weather_context->'location'->'latitude') IS DISTINCT FROM 'number'
     OR pg_catalog.jsonb_typeof(p_weather_context->'location'->'longitude') IS DISTINCT FROM 'number'
     OR pg_catalog.jsonb_typeof(p_weather_context->'requestedLocation'->'latitude') IS DISTINCT FROM 'number'
     OR pg_catalog.jsonb_typeof(p_weather_context->'requestedLocation'->'longitude') IS DISTINCT FROM 'number'
     OR COALESCE(p_weather_context->>'providerTimestamp', '') !~
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'
     OR COALESCE(p_weather_context->>'fetchedAt', '') !~
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$' THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'A valid current-weather observation is required.';
  END IF;
  IF (p_weather_context->>'providerTimestamp')::timestamptz > now() + interval '5 minutes'
     OR (p_weather_context->>'providerTimestamp')::timestamptz < now() - interval '30 minutes'
     OR (p_weather_context->>'fetchedAt')::timestamptz > now() + interval '5 minutes'
     OR (p_weather_context->>'fetchedAt')::timestamptz < now() - interval '10 minutes'
     OR pg_catalog.abs((p_weather_context->'location'->>'latitude')::numeric -
       (p_weather_context->'requestedLocation'->>'latitude')::numeric) > 0.25
     OR pg_catalog.abs((p_weather_context->'location'->>'longitude')::numeric -
       (p_weather_context->'requestedLocation'->>'longitude')::numeric) > 0.25 THEN
    RAISE EXCEPTION USING ERRCODE = 'P1006',
      MESSAGE = 'Current weather is stale or for another location. Please retry.';
  END IF;

  -- V2 computes demand solely from saved baseline/scenario and performs FEFO,
  -- sales, inventory, costing, history, and audit changes under its locks.
  completed := public.complete_pos_simulation_v2(
    p_actor_user_id, p_date, weather_condition);
  -- Recheck after v2's locks; a queued request must not commit if the bakery
  -- date advanced or the supplied observation aged out while it waited.
  SELECT (pg_catalog.clock_timestamp() AT TIME ZONE timezone)::date INTO bakery_day
  FROM public.bakery_settings WHERE singleton_guard = true FOR SHARE;
  IF bakery_day IS DISTINCT FROM p_date THEN
    RAISE EXCEPTION USING ERRCODE = 'P1007',
      MESSAGE = 'The bakery date changed while simulation was waiting. Retry.';
  END IF;
  IF (p_weather_context->>'providerTimestamp')::timestamptz <
       pg_catalog.clock_timestamp() - interval '30 minutes' THEN
    RAISE EXCEPTION USING ERRCODE = 'P1006',
      MESSAGE = 'Current weather became stale while simulation was waiting. Retry.';
  END IF;

  UPDATE public.daily_results SET
    simulation_method = 'INDEPENDENT_CURRENT_WEATHER_V3',
    simulation_snapshot = simulation_snapshot || pg_catalog.jsonb_build_object(
      'method', 'INDEPENDENT_CURRENT_WEATHER_V3',
      'currentWeather', p_weather_context),
    notes = 'SIMULATION_GENERATED; independent baseline with current weather v3'
  WHERE result_date = p_date AND simulation_method = 'INDEPENDENT_BASELINE_V2';

  UPDATE public.daily_sales_records AS sales SET
    validation_notes = 'Official atomic POS simulation v3; source is linked DailyResult'
  FROM public.daily_results AS result
  WHERE sales.source_daily_result_id = result.id AND result.result_date = p_date
    AND sales.data_origin = 'SIMULATION_GENERATED';

  SELECT pg_catalog.jsonb_agg(
    (item || pg_catalog.jsonb_build_object(
      'simulationMethod', 'INDEPENDENT_CURRENT_WEATHER_V3')) ||
    pg_catalog.jsonb_build_object('simulationSnapshot',
      item->'simulationSnapshot' || pg_catalog.jsonb_build_object(
        'method', 'INDEPENDENT_CURRENT_WEATHER_V3',
        'currentWeather', p_weather_context)) ORDER BY position)
  INTO updated_items
  FROM pg_catalog.jsonb_array_elements(completed->'items')
    WITH ORDINALITY AS entries(item, position);
  RETURN pg_catalog.jsonb_set(completed, '{items}', updated_items);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_pos_simulation_v2(uuid, date, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_pos_simulation_v3(uuid, date, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_simulation_v3(uuid, date, jsonb)
  TO service_role;

COMMIT;
