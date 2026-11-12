BEGIN;

ALTER TABLE public.calendar_events
  ADD COLUMN provider text,
  ADD COLUMN state_code text,
  ADD COLUMN provider_source_reference text,
  ADD COLUMN subject_to_change boolean,
  ADD COLUMN is_current boolean NOT NULL DEFAULT true,
  ADD CONSTRAINT calendar_kl_provider_check CHECK (
    provider IS NULL OR
    (provider = 'MALAYSIA_HOLIDAY_API' AND state_code IS NOT NULL
      AND state_code = 'KUL'
      AND event_type = 'PUBLIC_HOLIDAY'
      AND provider_source_reference IS NOT NULL
      AND provider_source_reference LIKE 'https://%'
      AND subject_to_change IS NOT NULL)
  );
CREATE INDEX calendar_current_date_idx ON public.calendar_events(event_date)
  WHERE is_current;

-- Keep legacy manually entered events and their prediction links for audit,
-- but only provider-synchronised KL holidays inform new predictions.
UPDATE public.calendar_events SET is_current = false WHERE provider IS NULL;
ALTER TABLE public.calendar_events ALTER COLUMN is_current SET DEFAULT false;
REVOKE EXECUTE ON FUNCTION public.add_verified_calendar_event(
  uuid,date,text,text,text) FROM service_role;

CREATE TABLE public.kl_holiday_syncs (
  holiday_year integer PRIMARY KEY CHECK (holiday_year BETWEEN 2000 AND 2100),
  state_code text NOT NULL DEFAULT 'KUL' CHECK (state_code = 'KUL'),
  provider text NOT NULL DEFAULT 'MALAYSIA_HOLIDAY_API'
    CHECK (provider = 'MALAYSIA_HOLIDAY_API'),
  provider_source_reference text NOT NULL
    CHECK (provider_source_reference LIKE 'https://%'),
  published_event_count integer NOT NULL CHECK (published_event_count > 0),
  last_successful_at timestamptz NOT NULL,
  refresh_after timestamptz NOT NULL
    CHECK (refresh_after > last_successful_at)
);
ALTER TABLE public.kl_holiday_syncs ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.sync_kl_public_holidays(
  p_actor_user_id uuid, p_year integer, p_events jsonb,
  p_source_reference text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE entry jsonb; saved_count integer := 0; year_start date;
BEGIN
  PERFORM 1 FROM public.user_profiles WHERE user_id = p_actor_user_id
    AND role IN ('BAKERY_MANAGER','SYSTEM_ADMINISTRATOR')
    AND account_status = 'ACTIVE' FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active bakery role required.';
  END IF;
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2100 OR
     jsonb_typeof(p_events) IS DISTINCT FROM 'array' OR
     p_source_reference IS NULL OR
     p_source_reference NOT LIKE 'https://%' OR
     length(p_source_reference) > 500 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Incomplete KL holiday year.';
  END IF;
  IF jsonb_array_length(p_events) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Empty KL holiday year.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_events) AS item(value)
    GROUP BY item.value->>'date', trim(item.value->>'name')
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Duplicate KL holiday event.';
  END IF;
  year_start := make_date(p_year, 1, 1);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('kl-holidays:' || p_year::text, 0));
  LOCK TABLE public.daily_predictions IN SHARE ROW EXCLUSIVE MODE;
  -- Retain historical event IDs and prediction links; corrections only
  -- retire their use in future predictions.
  UPDATE public.calendar_events SET is_current = false
  WHERE provider = 'MALAYSIA_HOLIDAY_API' AND state_code = 'KUL'
    AND event_date >= year_start AND event_date < (year_start + interval '1 year');
  FOR entry IN SELECT value FROM jsonb_array_elements(p_events) AS item(value)
  LOOP
    IF jsonb_typeof(entry) IS DISTINCT FROM 'object' OR
       entry->>'date' IS NULL OR entry->>'name' IS NULL OR
       entry->>'sourceUrl' IS NULL OR
       (entry->>'date')::date < year_start OR
       (entry->>'date')::date >= (year_start + interval '1 year') OR
       length(trim(entry->>'name')) NOT BETWEEN 1 AND 120 OR
       entry->>'sourceUrl' NOT LIKE 'https://%' OR
       length(entry->>'sourceUrl') > 500 OR
       jsonb_typeof(entry->'subjectToChange') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid KL holiday event.';
    END IF;
    INSERT INTO public.calendar_events(event_date,event_type,event_name,
      source_reference,provider,state_code,provider_source_reference,
      subject_to_change,is_current)
    VALUES ((entry->>'date')::date,'PUBLIC_HOLIDAY',trim(entry->>'name'),
      entry->>'sourceUrl','MALAYSIA_HOLIDAY_API','KUL',entry->>'sourceUrl',
      (entry->>'subjectToChange')::boolean,true)
    ON CONFLICT ON CONSTRAINT calendar_events_date_type_name_key DO UPDATE
      SET provider = 'MALAYSIA_HOLIDAY_API', state_code = 'KUL',
          provider_source_reference = EXCLUDED.provider_source_reference,
          subject_to_change = EXCLUDED.subject_to_change,
          is_current = true,
          source_reference = coalesce(public.calendar_events.source_reference,
            EXCLUDED.source_reference);
    saved_count := saved_count + 1;
  END LOOP;
  INSERT INTO public.kl_holiday_syncs(holiday_year,provider_source_reference,
    published_event_count,last_successful_at,refresh_after)
  VALUES (p_year,p_source_reference,saved_count,now(),now() + interval '7 days')
  ON CONFLICT (holiday_year) DO UPDATE SET
    provider_source_reference = EXCLUDED.provider_source_reference,
    published_event_count = EXCLUDED.published_event_count,
    last_successful_at = EXCLUDED.last_successful_at,
    refresh_after = EXCLUDED.refresh_after;
  INSERT INTO public.system_logs(actor_user_id,event_type,entity_type,
    entity_id,outcome,severity,payload)
  VALUES (p_actor_user_id,'KL_HOLIDAYS_SYNCED',NULL,NULL,
    'SUCCESS','INFO',jsonb_build_object('year',p_year,'eventCount',saved_count));
  RETURN jsonb_build_object('year',p_year,'eventCount',saved_count,
    'stateCode','KUL');
END; $$;
REVOKE ALL ON FUNCTION public.sync_kl_public_holidays(uuid,integer,jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sync_kl_public_holidays(uuid,integer,jsonb,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.check_prediction_calendar_snapshot()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE selected jsonb;
BEGIN
  selected := NEW.context_snapshot->'calendarEventIds';
  IF selected IS NULL OR jsonb_typeof(selected) <> 'array' OR
     jsonb_array_length(selected) <> (
       SELECT count(*) FROM public.calendar_events
       WHERE event_date = NEW.target_date AND is_current
     ) OR EXISTS (
       SELECT 1 FROM public.calendar_events AS event
       WHERE event.event_date = NEW.target_date AND event.is_current
         AND NOT selected @> jsonb_build_array(event.id::text)
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Calendar context changed before prediction save.';
  END IF;
  RETURN NEW;
END; $$;

COMMIT;
