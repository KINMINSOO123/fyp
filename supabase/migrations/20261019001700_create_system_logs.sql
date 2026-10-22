BEGIN;

CREATE TABLE public.system_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id uuid
        REFERENCES public.user_profiles(user_id) ON DELETE RESTRICT,
    event_type text NOT NULL CHECK (length(trim(event_type)) > 0),
    entity_type text,
    entity_id uuid,
    outcome text NOT NULL CHECK (outcome IN ('SUCCESS', 'FAILURE')),
    severity text NOT NULL DEFAULT 'INFO'
        CHECK (severity IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(payload) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_logs_entity_reference_check
        CHECK (
            (entity_type IS NULL AND entity_id IS NULL)
            OR (
                entity_type IS NOT NULL
                AND length(trim(entity_type)) > 0
                AND entity_id IS NOT NULL
            )
        )
);

CREATE INDEX idx_system_logs_created
    ON public.system_logs (created_at DESC);
CREATE INDEX idx_system_logs_event
    ON public.system_logs (event_type, created_at DESC);
CREATE INDEX idx_system_logs_actor
    ON public.system_logs (actor_user_id, created_at DESC);
CREATE INDEX idx_system_logs_entity
    ON public.system_logs (entity_type, entity_id, created_at DESC);

ALTER TABLE public.system_logs ENABLE ROW LEVEL SECURITY;

-- Later Node audit services derive actor_user_id from validated identity;
-- NULL represents a system actor. Do not trust client-supplied actor fields.
-- Application permissions must make logs append-only and restrict audit reads.
-- This table migration alone does not prevent privileged updates/deletes.
-- Entity references are audit metadata rather than polymorphic foreign keys.
-- Sanitize payloads: never record passwords, access tokens or provider secrets.
-- Successful mutation audits belong to their transaction. A failed transaction
-- rolls its audit inserts back too; any retained failure event must be recorded
-- separately after rollback, without retaining partial business changes.

COMMIT;
