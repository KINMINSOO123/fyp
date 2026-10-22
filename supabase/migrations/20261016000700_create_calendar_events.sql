BEGIN;

CREATE TABLE public.calendar_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_date date NOT NULL,
    event_type text NOT NULL
        CHECK (event_type IN (
            'PUBLIC_HOLIDAY',
            'SCHOOL_HOLIDAY',
            'LOCAL_EVENT',
            'RELIGIOUS_HOLIDAY'
        )),
    event_name text NOT NULL CHECK (length(trim(event_name)) > 0),
    demand_multiplier numeric(6,3)
        CHECK (demand_multiplier IS NULL OR demand_multiplier > 0),
    fetched_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT calendar_events_date_type_name_key
        UNIQUE (event_date, event_type, event_name)
);

CREATE INDEX idx_calendar_events_date
    ON public.calendar_events (event_date);

-- Application-table reads and writes go through the protected Node API.
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

COMMIT;
