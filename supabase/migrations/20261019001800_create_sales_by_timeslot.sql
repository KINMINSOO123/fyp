BEGIN;

CREATE VIEW public.sales_by_timeslot
WITH (security_invoker = true)
AS
SELECT
    result.result_date AS sale_date,
    sale.time_slot,
    result.bread_category_id,
    SUM(sale.quantity) AS total_sold
FROM public.sales_transactions AS sale
JOIN public.daily_results AS result ON result.id = sale.daily_result_id
GROUP BY result.result_date, sale.time_slot, result.bread_category_id;

-- Reporting goes through Node, not direct Flutter application-table access.
REVOKE ALL ON public.sales_by_timeslot FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.sales_by_timeslot TO service_role;

-- This is a computed view, not a table or materialized view. No inserts or
-- refresh jobs are needed. Only groups with sales transactions appear.
-- security_invoker applies the querying role's underlying table permissions
-- and RLS behavior. Node must still authorize every reporting request.
-- Keep service-role credentials server-side. This view summarizes simulated
-- transactions; it is not extra revenue or extra sales to add to daily totals.

COMMIT;
