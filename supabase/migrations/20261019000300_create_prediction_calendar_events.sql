BEGIN;

CREATE TABLE public.prediction_calendar_events (
    daily_prediction_id uuid NOT NULL
        REFERENCES public.daily_predictions(id) ON DELETE RESTRICT,
    calendar_event_id uuid NOT NULL
        REFERENCES public.calendar_events(id) ON DELETE RESTRICT,
    PRIMARY KEY (daily_prediction_id, calendar_event_id)
);

CREATE INDEX idx_prediction_calendar_event
    ON public.prediction_calendar_events (calendar_event_id);

ALTER TABLE public.prediction_calendar_events ENABLE ROW LEVEL SECURITY;

-- The later prediction service records the events used for each prediction.
-- A prediction can have zero, one or multiple linked events; an event can
-- contribute to multiple predictions. The primary key prevents duplicate links.
-- These links provide traceability; POS must not reapply event multipliers.

COMMIT;
