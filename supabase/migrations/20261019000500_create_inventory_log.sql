BEGIN;

CREATE TABLE public.inventory_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    operation_id uuid NOT NULL,
    inventory_id uuid NOT NULL
        REFERENCES public.inventory(id) ON DELETE RESTRICT,
    batch_id uuid NOT NULL
        REFERENCES public.inventory_batches(id) ON DELETE RESTRICT,
    production_decision_id uuid
        REFERENCES public.production_decisions(id) ON DELETE RESTRICT,
    change_grams numeric(14,3) NOT NULL
        CHECK (change_grams <> 0 AND change_grams <> 'NaN'::numeric),
    reason text NOT NULL
        CHECK (reason IN (
            'RESTOCK', 'PRODUCTION_DEDUCTION', 'PRODUCTION_REVERSAL',
            'DISCARD', 'CORRECTION'
        )),
    effective_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_log_production_reference_check
        CHECK (
            reason NOT IN ('PRODUCTION_DEDUCTION', 'PRODUCTION_REVERSAL')
            OR production_decision_id IS NOT NULL
        ),
    CONSTRAINT inventory_log_movement_direction_check
        CHECK (
            (reason IN ('RESTOCK', 'PRODUCTION_REVERSAL') AND change_grams > 0)
            OR (reason IN ('PRODUCTION_DEDUCTION', 'DISCARD') AND change_grams < 0)
            OR reason = 'CORRECTION'
        )
);

CREATE INDEX idx_inventory_log_operation
    ON public.inventory_log (operation_id);
CREATE INDEX idx_inventory_log_inventory_date
    ON public.inventory_log (inventory_id, effective_date);
CREATE INDEX idx_inventory_log_batch
    ON public.inventory_log (batch_id);
CREATE INDEX idx_inventory_log_decision
    ON public.inventory_log (production_decision_id);

ALTER TABLE public.inventory_log ENABLE ROW LEVEL SECURITY;

-- Later Node transaction logic must validate that inventory and batch belong
-- to the same ingredient. Batch balances, inventory snapshots and movements
-- must be updated atomically; inserting a log alone does not change stock.
-- Production uses eligible batches in FEFO order and records exact movements
-- with the same operation_id for the operation. That ID alone does not prevent
-- duplicates; decision locks and unique operational links do so.
-- Batch unit-cost snapshots supply historical consumption costs.
-- PRODUCTION_REVERSAL is reserved for future work, not an enabled workflow.
-- Failed simulations must roll back, not create correction/reversal records.

COMMIT;
