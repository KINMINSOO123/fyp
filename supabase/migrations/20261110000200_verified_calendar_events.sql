BEGIN;

-- Legacy event rows retain null provenance; all new entries require a source.
ALTER TABLE public.calendar_events ADD COLUMN source_reference text
    CHECK (source_reference IS NULL OR
        length(trim(source_reference)) BETWEEN 1 AND 500);

CREATE FUNCTION public.add_verified_calendar_event(
    p_actor_user_id uuid, p_event_date date, p_event_type text,
    p_event_name text, p_source_reference text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE saved public.calendar_events%ROWTYPE;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'SYSTEM_ADMINISTRATOR'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
    END IF;
    IF p_event_date IS NULL OR p_event_type NOT IN
       ('PUBLIC_HOLIDAY', 'SCHOOL_HOLIDAY', 'LOCAL_EVENT', 'RELIGIOUS_HOLIDAY')
       OR p_event_name IS NULL OR length(trim(p_event_name)) NOT BETWEEN 1 AND 120
       OR p_source_reference IS NULL OR
          length(trim(p_source_reference)) NOT BETWEEN 1 AND 500 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid calendar event.';
    END IF;
    -- Serialize with prediction writes for this date. The prediction insert
    -- trigger below rejects a stale event list if this event commits first.
    LOCK TABLE public.daily_predictions IN SHARE ROW EXCLUSIVE MODE;
    IF EXISTS (SELECT 1 FROM public.daily_predictions
        WHERE target_date = p_event_date) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
            MESSAGE = 'Predictions already exist for this calendar date.';
    END IF;
    INSERT INTO public.calendar_events (
        event_date, event_type, event_name, source_reference
    ) VALUES (p_event_date, p_event_type, trim(p_event_name),
        trim(p_source_reference))
    RETURNING * INTO saved;
    INSERT INTO public.system_logs (actor_user_id, event_type,
        entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, 'CALENDAR_EVENT_RECORDED',
        'calendar_events', saved.id, 'SUCCESS', 'INFO',
        jsonb_build_object('date', saved.event_date,
            'sourceReference', saved.source_reference));
    RETURN jsonb_build_object('id', saved.id, 'eventDate', saved.event_date,
        'eventType', saved.event_type, 'eventName', saved.event_name,
        'sourceReference', saved.source_reference);
END;
$$;

CREATE FUNCTION public.check_prediction_calendar_snapshot()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE selected jsonb;
BEGIN
    selected := NEW.context_snapshot->'calendarEventIds';
    IF selected IS NULL OR jsonb_typeof(selected) <> 'array' OR
       jsonb_array_length(selected) <> (
           SELECT count(*) FROM public.calendar_events
           WHERE event_date = NEW.target_date
       ) OR EXISTS (
           SELECT 1 FROM public.calendar_events AS event
           WHERE event.event_date = NEW.target_date
             AND NOT selected @> jsonb_build_array(event.id::text)
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Calendar context changed before prediction save.';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER check_prediction_calendar_snapshot_before_insert
BEFORE INSERT ON public.daily_predictions FOR EACH ROW
EXECUTE FUNCTION public.check_prediction_calendar_snapshot();

REVOKE ALL ON FUNCTION public.add_verified_calendar_event(
    uuid, date, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_verified_calendar_event(
    uuid, date, text, text, text) TO service_role;

COMMIT;
