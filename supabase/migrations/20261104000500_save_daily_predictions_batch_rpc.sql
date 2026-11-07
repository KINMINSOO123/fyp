BEGIN;

ALTER TABLE public.daily_predictions
    ADD COLUMN context_snapshot jsonb
        CHECK (context_snapshot IS NULL OR
               jsonb_typeof(context_snapshot) = 'object');

CREATE OR REPLACE FUNCTION public.save_daily_predictions_batch_with_audit(
    p_actor_user_id uuid,
    p_target_date date,
    p_predictions jsonb
)
RETURNS TABLE (id uuid, bread_category_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    bakery_timezone text;
    active_category_count integer;
    item jsonb;
    category_id_value uuid;
    prediction_mode_value text;
    model_id_value uuid;
    weather_id_value uuid;
    confidence_value numeric;
    prediction_id_value uuid;
    event_id_value uuid;
    event_text text;
    seen_categories uuid[] := ARRAY[]::uuid[];
    seen_events uuid[];
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.user_profiles AS actor
        WHERE actor.user_id = p_actor_user_id
          AND actor.role = 'BAKERY_MANAGER'
          AND actor.account_status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;

    SELECT settings.timezone INTO bakery_timezone
    FROM public.bakery_settings AS settings
    WHERE settings.singleton_guard = true
    FOR SHARE;
    IF bakery_timezone IS NULL OR p_target_date IS NULL OR
       p_target_date <> (now() AT TIME ZONE bakery_timezone)::date + 1 THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'The next bakery date is required.';
    END IF;

    IF p_predictions IS NULL OR jsonb_typeof(p_predictions) <> 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'A complete prediction array is required.';
    END IF;

    -- Lock the active catalogue against concurrent deactivation and serialize
    -- this operation with activation/restoration, which lock category rows.
    PERFORM 1 FROM public.bread_categories AS category
    WHERE category.is_active = true
    FOR SHARE;
    SELECT count(*) INTO active_category_count
    FROM public.bread_categories AS category
    WHERE category.is_active = true;
    IF active_category_count = 0 OR
       jsonb_array_length(p_predictions) <> active_category_count THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Predictions must cover every active category.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.daily_predictions AS prediction
        WHERE prediction.target_date = p_target_date
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'Predictions already exist for this date.';
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(p_predictions) AS rows(value)
    LOOP
        IF jsonb_typeof(item) <> 'object' OR
           jsonb_typeof(item->'calendarEventIds') <> 'array' OR
           jsonb_typeof(item->'contextSnapshot') <> 'object' THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Invalid prediction context.';
        END IF;
        category_id_value := (item->>'breadCategoryId')::uuid;
        prediction_mode_value := item->>'predictionMode';
        model_id_value := (item->>'modelVersionId')::uuid;
        weather_id_value := (item->>'weatherRecordId')::uuid;
        confidence_value := (item->>'confidence')::numeric;
        IF category_id_value IS NULL OR
           category_id_value = ANY(seen_categories) OR
           NOT EXISTS (
               SELECT 1 FROM public.bread_categories AS category
               WHERE category.id = category_id_value
                 AND category.is_active = true
           ) OR
           (item->>'predictedUnitsSold') IS NULL OR
           (item->>'predictedUnitsSold')::integer < 0 THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Invalid category or predicted quantity.';
        END IF;
        seen_categories := array_append(seen_categories, category_id_value);

        IF weather_id_value IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.weather_records AS weather
            WHERE weather.id = weather_id_value
              AND weather.weather_date = p_target_date
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Weather context belongs to another date.';
        END IF;

        IF prediction_mode_value = 'MODEL' THEN
            IF model_id_value IS NULL OR confidence_value IS NULL OR
               confidence_value < 0 OR confidence_value > 100 OR
               NOT EXISTS (
                   SELECT 1 FROM public.ml_model_versions AS model
                   WHERE model.id = model_id_value
                     AND model.bread_category_id = category_id_value
                     AND model.model_type = 'RANDOM_FOREST'
                     AND model.lifecycle_status = 'ACTIVE'
               ) OR
               (SELECT count(DISTINCT sales.sales_date)
                FROM public.daily_sales_records AS sales
                WHERE sales.bread_category_id = category_id_value
                  AND sales.sales_date < p_target_date
                  AND sales.is_validated = true) < 30 THEN
                RAISE EXCEPTION USING ERRCODE = '22023',
                    MESSAGE = 'The active model or history eligibility changed.';
            END IF;
        ELSIF prediction_mode_value = 'COLD_START' THEN
            IF model_id_value IS NOT NULL OR confidence_value IS NOT NULL THEN
                RAISE EXCEPTION USING ERRCODE = '22023',
                    MESSAGE = 'Cold-start confidence and model must be null.';
            END IF;
        ELSE
            RAISE EXCEPTION USING ERRCODE = '22023',
                MESSAGE = 'Unsupported prediction mode.';
        END IF;

        INSERT INTO public.daily_predictions AS inserted (
            target_date, bread_category_id, predicted_units_sold,
            confidence, prediction_mode, model_version_id,
            weather_record_id, context_snapshot
        ) VALUES (
            p_target_date, category_id_value,
            (item->>'predictedUnitsSold')::integer,
            confidence_value, prediction_mode_value, model_id_value,
            weather_id_value, item->'contextSnapshot'
        ) RETURNING inserted.id INTO prediction_id_value;

        seen_events := ARRAY[]::uuid[];
        FOR event_text IN
            SELECT jsonb_array_elements_text(item->'calendarEventIds')
        LOOP
            event_id_value := event_text::uuid;
            IF event_id_value = ANY(seen_events) OR NOT EXISTS (
                SELECT 1 FROM public.calendar_events AS event
                WHERE event.id = event_id_value
                  AND event.event_date = p_target_date
            ) THEN
                RAISE EXCEPTION USING ERRCODE = '22023',
                    MESSAGE = 'Invalid or duplicate calendar event.';
            END IF;
            seen_events := array_append(seen_events, event_id_value);
            INSERT INTO public.prediction_calendar_events (
                daily_prediction_id, calendar_event_id
            ) VALUES (prediction_id_value, event_id_value);
        END LOOP;

        id := prediction_id_value;
        bread_category_id := category_id_value;
        RETURN NEXT;
    END LOOP;

    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'PREDICTIONS_GENERATED', NULL, NULL,
        'SUCCESS', 'INFO',
        jsonb_build_object(
            'target_date', p_target_date,
            'category_count', active_category_count,
            'category_ids', seen_categories
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.save_daily_predictions_batch_with_audit(
    uuid, date, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_daily_predictions_batch_with_audit(
    uuid, date, jsonb
) TO service_role;

COMMIT;
