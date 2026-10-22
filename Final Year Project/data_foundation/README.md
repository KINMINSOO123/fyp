# Module 0: Data Foundation Design Guide

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

Reconciled **11 October 2026** against the latest `RSW_SooKinMin_Project1 (1).docx`, especially Section 4.5 and Tables 4.14-4.20. This README contains **proposed SQL and DTO examples**, not implemented files, migration output or verified behaviour. See [MODULE.md](MODULE.md), [canonical field dictionary/ERD](../../database_canonical_design.md) and [planned checks](../../database_schema_verification.md). The DOCX controls; historical July planning labels do not.

## 1. Build dependencies and scope

Technical module 0 supports all eight report functional modules through shared persistence/contracts; [MODULE Section 1](MODULE.md#1-purpose-scope-and-functional-mapping) maps them to technical modules 0-6. Retain next-day prediction, inventory-aware recommendations, POS simulation and leftover/donation management. One Android bakery is in scope; customer ordering/payment, delivery/marketplace, real POS hardware, multiple branches and automatic background scheduling are excluded.

Plan schema/contracts first, then Node Controllers/Services/Repos, ML DTOs/services, joint inventory/confirmation, atomic POS, leftover/reporting and notifications/checks. Four bread categories and five ingredients are example seed entries, not hard-coded loops/caps. Design and test up to 20 configured active categories.

## 2. Catalogue and naming checklist

| Group | Tables | Count |
|---|---|---:|
| Access/configuration | user_profiles, bakery_settings, system_settings | 3 |
| Catalogue/inventory | bread_categories, ingredients, recipes, inventory, inventory_batches, inventory_log | 6 |
| Context/prediction/models | weather_records, calendar_events, daily_sales_records, ml_model_versions, model_evaluations, feature_importance, daily_predictions, prediction_calendar_events | 8 |
| Production/POS/surplus | production_decisions, daily_production, daily_results, sales_transactions, charity_partners, donations, waste_records | 7 |
| Notifications/audit | notifications, notification_preferences, fcm_tokens, notification_deliveries, system_logs | 5 |
| **Total public tables** | | **29** |

One external `auth.users` table and one computed `sales_by_timeslot` view are additional objects, not extra application tables. There are **0 PostgreSQL enum types** and **21 CHECK-controlled domains**, listed in canonical Section 3. Do not revive the historical "19 tables" count. Schema keys, constraints and all field details live in canonical Section 5; no smaller README list overrides it.

Use database snake_case, TypeScript/Dart camelCase and explicit Pydantic transport mappings. Controlled values remain uppercase. Preserve `recipient_user_id`, `source_daily_result_id`, `external_source_reference`, `prediction_calendar_events` and `sales_prediction_error` spellings. Do not introduce SimulationRun/LeftoverRecord tables. Recommendation and report objects are DTOs; leftover persists on DailyResult, allocations in normalized child tables.

## 3. Proposed critical constraints

These fragments illustrate the planned design; they are not complete runnable migrations.

```sql
-- Exactly one application role; credentials remain in Supabase Auth.
CHECK (role IN ('BAKERY_MANAGER', 'SYSTEM_ADMINISTRATOR'));
CHECK (account_status IN ('ACTIVE', 'INACTIVE'));
-- All three are required for at most one bakery-settings row.
-- singleton_guard BOOLEAN NOT NULL DEFAULT TRUE
CHECK (singleton_guard = TRUE);
UNIQUE (singleton_guard);

-- daily_predictions: confidence column is nullable, with mode coupling.
CHECK (
  (prediction_mode = 'MODEL' AND model_version_id IS NOT NULL
   AND confidence IS NOT NULL AND confidence BETWEEN 0 AND 100)
  OR
  (prediction_mode = 'COLD_START' AND model_version_id IS NULL
   AND confidence IS NULL)
);
UNIQUE (target_date, bread_category_id);

-- daily_sales_records: do not overload an external import reference as an FK.
CHECK (
  (data_origin = 'SIMULATION_GENERATED'
   AND source_daily_result_id IS NOT NULL
   AND external_source_reference IS NULL AND is_validated = TRUE)
  OR
  (data_origin IN ('ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL')
   AND source_daily_result_id IS NULL
   AND external_source_reference IS NOT NULL
   AND length(trim(external_source_reference)) > 0)
);
UNIQUE (sales_date, bread_category_id, data_origin);
CREATE UNIQUE INDEX one_history_per_result
  ON daily_sales_records(source_daily_result_id)
  WHERE data_origin = 'SIMULATION_GENERATED';

-- These distinct constraints belong to their respective tables.
-- production_decisions: UNIQUE (prediction_id)
-- daily_production: UNIQUE (production_decision_id)
-- daily_results: UNIQUE (daily_production_id), UNIQUE (prediction_id)
-- Matching category/date composite keys/FKs also apply (canonical Section 5).
CREATE UNIQUE INDEX one_active_model_per_category
  ON ml_model_versions(bread_category_id)
  WHERE lifecycle_status = 'ACTIVE';
```

NOT NULL constraints, foreign keys and CHECK domains supplement these fragments. `MODEL` also requires a valid active Random Forest model at generation time and at least 30 distinct selected daily observations; this is Service validation, not a static FK claim that historical model references must remain active forever. Enforce the final active administrator transactionally with locking, not a row-local CHECK.

`system_settings` validates allowed keys and JSON types, retains updater identity and excludes credentials/secrets. `bakery_settings` is a single configured bakery row, not a tenant/branch model. Master records and tokens use soft deactivation; historical foreign keys restrict deletion.

## 4. Shared DTO and mode mapping examples

```ts
// Proposed contract only; no generated or implemented TypeScript file exists.
type DataOrigin =
  | 'ACTUAL_TRANSACTION'
  | 'IMPORTED_HISTORICAL'
  | 'SIMULATION_GENERATED';
type UserRole = 'BAKERY_MANAGER' | 'SYSTEM_ADMINISTRATOR';
type AccountStatus = 'ACTIVE' | 'INACTIVE';
type ProductionOption = 'ACCEPT_RECOMMENDATION' | 'REDUCE' | 'MANUAL_OVERRIDE';
type DonationStatus = 'PENDING' | 'COLLECTED' | 'COMPLETED' | 'CANCELLED';
type PushStatus = 'PENDING' | 'SUBMITTED' | 'DELIVERED' | 'FAILED' | 'SKIPPED';

type PredictionBase = {
  id: string;
  breadCategoryId: string;
  targetDate: string;
  predictedUnitsSold: number; // validated nonnegative integer
};
type PredictionDTO = PredictionBase & (
  | { predictionMode: 'MODEL'; modelVersionId: string;
      confidence: number; lowConfidence: boolean }
  | { predictionMode: 'COLD_START'; modelVersionId: null;
      confidence: null; lowConfidence: true }
);
```

These are selected shared examples, not an assertion that the full type catalogue has seven aliases. The complete 21 controlled domains are in canonical Section 3. Runtime Zod/Pydantic/Dart validation must preserve this discriminated nullability. Validate finite values, whole quantities, UUID/date formatting and 0..100 numerical model confidence. Do not coerce null to zero or render a cold-start percentage.

```json
{
  "id": "44444444-4444-4444-8444-444444444444",
  "breadCategoryId": "11111111-1111-4111-8111-111111111111",
  "targetDate": "2026-10-12",
  "predictedUnitsSold": 12,
  "predictionMode": "COLD_START",
  "modelVersionId": null,
  "confidence": null,
  "lowConfidence": true
}
```

For MODEL, `ConfidenceService` applies `confidence = 100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))` and `predicted_units_sold = max(0, round(mu))`. MODEL below the configured initial 75% threshold is Low Confidence; confidence is tree agreement, not accuracy probability. COLD_START averages available selected valid units sold for Bc (configured base only when none exist), applies weekday/monsoon/weather/holiday factors `max(0, round(Bc*Dt*Mt*Wt*Ht))` and returns the null-valued contract above.

## 5. History selection and model lifecycle

A proposed Repo query selects only one validated daily observation per category/day:

```sql
SELECT DISTINCT ON (bread_category_id, sales_date)
       id, bread_category_id, sales_date, units_sold,
       data_origin, source_daily_result_id, external_source_reference
FROM daily_sales_records
WHERE is_validated = TRUE
ORDER BY bread_category_id, sales_date,
  CASE data_origin
    WHEN 'ACTUAL_TRANSACTION' THEN 1
    WHEN 'IMPORTED_HISTORICAL' THEN 2
    WHEN 'SIMULATION_GENERATED' THEN 3
  END, id;
```

Count distinct days after this selection for the 30-observation threshold. `DailySalesRecord.unitsSold` is the training and comparable error-monitoring target. `estimatedDemand = unitsSold + lostSales` is analysis only. Every report/evaluation retains simulation-origin labels.

`ModelManagementService` through `MlModelVersionRepo`, `ModelEvaluationRepo` and `FastApiMlClient` handles separate administrator training, evaluation, activation and restoration requests. Chronologically later holdout data is used neither for fitting nor parameter selection; RF/LR use identical training/test observations. Retain holdout manifest/fingerprint metadata for the same-dataset MAE comparison. Reject activation if candidate MAE exceeds active model MAE or valid comparable evaluation is missing; rollback preserves current active model. MAE/RMSE include zeros; MAPE excludes only zero actuals. Undefined MAPE/R^2 is null, not a perfect value. Aspirational MAPE/R^2 targets are optional, not report-mandated acceptance gates.

## 6. Shared inventory and atomic POS contract

`RecommendationEngine` reads stored predictions and allocates one temporary stock balance. Reserve confirmed unprocessed decisions first, report shortages, then visit unconfirmed active categories in display_order. Compute whole-unit maximum from remaining recipe ingredient balances, recommend min(prediction, maximum), and subtract usage before the next category. On confirmation/revision `ProductionDecisionService` validates the combined outstanding plan and replaces the old quantity rather than adding both. No stock changes at confirmation. Processed decisions are identified by an existing `daily_production.production_decision_id` and excluded from commitments. Manager overrides require a reason and joint feasibility; no automatic production buffer.

A proposed `InventoryBatchRepo` query for FEFO is:

```sql
SELECT id, ingredient_id, received_date, expiry_date,
       remaining_quantity_grams, unit_cost
FROM inventory_batches
WHERE ingredient_id = $1
  AND status = 'ACTIVE'
  AND received_date <= $2
  AND expiry_date >= $2
  AND remaining_quantity_grams > 0
ORDER BY expiry_date ASC, received_date ASC, id ASC
FOR UPDATE;

CREATE INDEX idx_inventory_batches_fefo
  ON inventory_batches(ingredient_id, expiry_date, received_date, id)
  WHERE status = 'ACTIVE';
```

`$2` is the production date; expiry date is the last usable date in this planning convention. Expiry filtering excludes unusable batches; FEFO selects the earliest expiry first, then receipt date and ID. Batches/ingredients are locked in a consistent order for concurrent operations.

Official simulation requires selected-date stored prediction and manager confirmation; default date is current bakery-local date. `PosSimulationService` and `TransactionRecordingService` through `SimulationCommitRepo` own one PostgreSQL transaction/RPC. Lock decisions and relevant inventory; revalidate all outstanding commitments; deduct selected confirmed decisions FEFO once before sales processing. Use the stored contextual prediction plus time-slot/stochastic variation without multiplying weather/holiday/season again. Persist batch/snapshot changes, inventory_log movements, daily_production, sales_transactions, daily_results and one validated SIMULATION_GENERATED history row per result in the same commit. Any failure rolls back every change. Uniqueness plus decision locks handles duplicate requests with `409 ALREADY_SIMULATED` and a stored-result link, without further inventory/history mutation; operation_id merely groups movements. A batch of categories is all-or-nothing.

Do not expose producedOverride or fallback-to-recommendation operational paths. Test-only inputs must not persist operational records. Re-simulation is future work until exact original-batch reversal, linked history/allocations and idempotency have an explicit atomic policy. No correction batch or extra SimulationRun table substitutes for rollback.

## 7. Reporting, allocation and notification persistence

| Stored/derived value | Required calculation or invariant |
|---|---|
| estimated_demand | units_sold + lost_sales |
| leftover | produced - units_sold |
| sales_prediction_error | units_sold - predicted_units_sold, signed |
| leftover_rate_pct | leftover / produced * 100; NULL/Not Applicable at produced=0 |
| ingredient_cost | Sum actual FEFO deduction grams/1000 * immutable batch.unit_cost (canonical MYR/kg snapshot convention) |
| revenue | Sum transaction quantity * immutable unit_price; do not add transaction totals to DailyResult totals again |
| gross_profit / margin | revenue - ingredient_cost; profit/revenue * 100; negative allowed, revenue=0 -> Not Applicable |
| remaining_unallocated_leftover | leftover - donated - wasted; never negative |

All financial outputs are reporting-only simulated estimates. Current ingredient prices cannot recost history; donated/unallocated leftovers are not automatically discarded waste. Manual reports use date/period/category filters, weekly reports and supported CSV/PDF exports from the same calculations as UI.

`LeftoverManagementService` locks DailyResult before a manager-confirmed positive donation/waste allocation, validates active charity or disposal reason, and commits allocation/balance/audit together. Category comes through DailyResult. `PATCH /api/donations/:id/status` supports report status concepts PENDING, COLLECTED, COMPLETED and CANCELLED; old RECORDED/PICKED_UP/DELIVERED map to the first three. Cancellation/reallocation accounting and reversible transitions remain an open decision, not an invented stock-release rule. No automatic donation is planned.

Each notification has recipient_user_id. Preferences are per user and type; valid active FCM tokens must belong to that recipient. Push requires explicit opt-in and OS permission; missing/disabled preference or missing token produces SKIPPED. Track PENDING, SUBMITTED, DELIVERED, FAILED and SKIPPED per attempt/device, with skip_reason nonblank only for SKIPPED; provider submission does not establish delivery. Include expiry/stock, confidence, lost-sales, surplus, donation status and external/model/system failure events. Read state/event deduplication is recipient-scoped, never global.

For the report's foreground Realtime, enable RLS and only a narrow authenticated `notifications` SELECT policy for the ACTIVE intended recipient and enabled in-app preference. A restricted read-only helper can validate current-user profile/preferences without exposing those tables. Supabase Auth and FCM are the other platform exceptions. All ordinary CRUD and notification mark-read/preference/token writes use Node. FastAPI has no Supabase database client/credentials. Pending indicators are derived on open/refresh/state requests; no daily 06:00/18:00 scheduler or automatic business action.

## 8. Planned verification and completion evidence

After implementation, verify every catalogue/constraint/DTO mapping against the canonical document. Test inactive/wrong-role rejection and final-admin protection, 29/30 distinct-day gate and origin priority, null cold confidence/formula boundaries, higher-MAE activation rejection, shared ingredients/revisions, expiry-order FEFO with conflicting expiry order, duplicate simulation and fault injection at every commit stage, concurrent leftover allocation, recipient-only Realtime/read state, push opt-in/delivery tracking, historical batch/sale cost snapshots and CSV/PDF totals.

Reference environment: Android 10+, at least 4 GB RAM, stable >=10 Mbps, up to 20 categories, 365 daily records/category, 50 displayed list records. Require >=95% specified screen requests within 3 s; prediction/recommendation within 15 s; 12-hour simulation or seven-day report within 30 s. Plan 360x640-412x915 dp checks and >=80% independent UAT task completion without inventing participant counts/results.

Implementation artifacts (migrations, generated types, Repos, transaction functions, indexes/policies and runtime tests) remain future work. Current evidence is Markdown reconciliation only. Follow the [verification plan](../../database_schema_verification.md) when those artifacts exist; do not report design examples as implemented files or passed checks.
