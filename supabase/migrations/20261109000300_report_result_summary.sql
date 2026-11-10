BEGIN;

-- One row per completed category/day. Allocation totals are already grouped
-- inside leftover_allocation_summary, avoiding donation x waste fan-out.
-- The lateral history lookup keeps the report's comparable observation and
-- its provenance distinct from the stored simulation result.
CREATE VIEW public.report_result_summary
WITH (security_invoker = true)
AS
SELECT result.id AS daily_result_id,
       result.result_date, result.bread_category_id,
       category.name AS bread_category_name,
       category.display_order,
       result.predicted_units_sold, result.produced,
       result.units_sold, result.lost_sales,
       result.estimated_demand, result.leftover,
       result.remaining_unallocated_leftover,
       result.sales_prediction_error,
       result.revenue, result.ingredient_cost, result.gross_profit,
       allocation.donated, allocation.wasted,
       selected.units_sold AS evaluation_units_sold,
       selected.data_origin AS evaluation_data_origin
FROM public.daily_results AS result
JOIN public.bread_categories AS category
  ON category.id = result.bread_category_id
JOIN public.leftover_allocation_summary AS allocation
  ON allocation.daily_result_id = result.id
LEFT JOIN LATERAL (
    SELECT history.units_sold, history.data_origin
    FROM public.daily_sales_records AS history
    WHERE history.sales_date = result.result_date
      AND history.bread_category_id = result.bread_category_id
      AND history.is_validated = true
    ORDER BY CASE history.data_origin
        WHEN 'ACTUAL_TRANSACTION' THEN 1
        WHEN 'IMPORTED_HISTORICAL' THEN 2
        WHEN 'SIMULATION_GENERATED' THEN 3
        ELSE 4 END,
        history.id
    LIMIT 1
) AS selected ON true;

REVOKE ALL ON public.report_result_summary FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.report_result_summary TO service_role;

-- Revenue and ingredient cost are the committed DailyResult snapshots: the
-- POS transaction calculated revenue from sale unit-price snapshots and cost
-- from the exact FEFO batch movement unit-cost snapshots. No current master
-- prices or detailed transaction rows are added again during reporting.
COMMIT;
