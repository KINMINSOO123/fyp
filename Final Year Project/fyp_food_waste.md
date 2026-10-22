# Smart Bakery project plan

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

Reconciled on 2026-10-11 against the latest **RSW_SooKinMin_Project1** DOCX, especially Sections 1.1, 1.4, 3.4-3.6 and Chapter 4. The repository report mirror is [RSW_SooKinMin_Project1.docx.md](../RSW_SooKinMin_Project1.docx.md). The DOCX governs if the mirror differs. The user-deleted `FYP Report.md` remains deleted. Earlier July 2026 planning claims do not establish approval of this design.

This is a proposed design. The repository contains a Flutter counter starter and planning documents; backend, ML, database, reports and test outcomes described here are not implemented or verified.

## 1. Objectives and scope

Retain the report's four objectives: next-day sales prediction; inventory-aware production recommendations; POS simulation for testing and validation; and leftover/donation management. The application serves one bakery on Android. Customer ordering/payment, delivery, marketplace functions, real POS hardware, multi-branch operation and automatic background scheduling are outside scope. Financial summaries are reporting-only simulated estimates, not payment/accounting functions or evidence of real-world savings.

Four bread categories and five ingredients are example seeds. Operations iterate over configured active categories, with the reference workload of up to 20 categories and 365 historical daily records per category. Administration supports changing categories, recipes, ingredients and settings without changing source code.

### Functional modules and technical build mapping

The eight functional modules in Section 1.4.2 and the seven technical build modules describe different decompositions; neither replaces the other.

| Functional module | Responsibilities | Technical modules 0-6 |
|---|---|---|
| 1 User and Access Management | Login/logout, own profile, one stored role, active account, administrator user management | 0 data foundation; 1 Node middleware; 5 mobile views; 6 verification |
| 2 Demand Prediction | Validated history, context, model/cold start, confidence, administrator model lifecycle | 0; 1; 2 ML prediction; 5; 6 |
| 3 Inventory and Smart Production Recommendation | Admin master data/batches; manager jointly feasible production plan | 0; 1; 3 inventory integration; 5; 6 |
| 4 POS and Sales Simulation | Confirmed production, atomic FEFO deduction, simulated sales/history | 0; 1; 3; 4 POS simulation; 5; 6 |
| 5 Leftover, Donation and Waste Management | Confirmed allocation, charity administration, donation status | 0; 1; 5 donation/dashboard; 6 |
| 6 Reporting and Dashboard | Role-specific summaries and filtered on-demand CSV/PDF exports | 0; 1; 4; 5; 6 |
| 7 Alerts and Notifications | Recipient-only foreground Realtime, opt-in FCM, pending indicators | 0; 1; 3; 4; 5; 6 operation reminders/testing |
| 8 System Administration | Users/roles, settings, external configuration, audit, model lifecycle | 0; 1; 2; 3; 5; 6 |

## 2. Architecture and permissions

[ARCHITECTURE.md](ARCHITECTURE.md) defines the layered client-server MVC design. Flutter protected business requests follow `View -> ApiClient -> Controller -> Service -> Repo -> PostgreSQL`. Services use external adapters; `FastApiMlClient` supplies validated DTOs to thin FastAPI routes and Python ML Services. FastAPI has no Supabase database client, database credentials or application Repos. Route registration modules are not UML classes.

The report explicitly permits Flutter Supabase Authentication, recipient-scoped Supabase Realtime notification events while foregrounded, and FCM background notification reception (Sections 4.2.4, 4.8). Ordinary application-table CRUD and every notification write/mark-read action go through Node. The narrowly scoped authenticated notification SELECT policy is an exception for Realtime, not general table access.

JWT signature/issuer/audience/expiry validation and an ACTIVE `user_profiles` lookup precede permission checks. Exactly one stored role is permitted: `BAKERY_MANAGER` or `SYSTEM_ADMINISTRATOR`. No email inference, client actor/role fields or administrator inheritance of manager-only operations is allowed.

Managers generate predictions, review/confirm production, run simulation, and allocate leftovers/update donation status. Administrators manage master data, batches, charity partners, users/roles, settings and model lifecycle. Both manage their own profiles/personal notifications and view permitted reports/dashboard data. Preserve the final active administrator under concurrent account changes. See [Node plan](nodejs_middleware/MODULE.md) for concrete Services, Repos, endpoints and UI ownership.

## 3. Prediction and model lifecycle

Use `DailySalesRecord.unitsSold` for training and comparable performance evaluation. `estimatedDemand = unitsSold + lostSales` is analytical only. Exact `DataOrigin` values are `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, `SIMULATION_GENERATED`. Select one validated record per category/day in that priority order before counting observations, constructing features, splitting data or evaluating predictions. Imported/source records retain provenance; simulation labels persist into metrics and reports.

A category uses Random Forest only with at least 30 distinct validated daily observations and a valid active model. `ConfidenceService` implements Section 4.9.2, with mu the mean of the tree predictions and sigma their standard deviation:

```text
mu = sum(tree_predictions) / tree_count
predicted_units_sold = max(0, round(mu))
confidence = 100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))
```

Numerical confidence is in [0, 100]. MODEL requires a model-version reference and numerical confidence; below the configurable threshold (initially 75%) it is Low Confidence. It expresses tree agreement, not the probability of accuracy or an improvement guarantee. No forced floor/ceiling mapping applies.

`ColdStartService` uses Bc = mean of available valid units-sold observations for that category, using the configured base only if none exist. Dt, Mt, Wt and Ht are configured weekday, monsoon, weather and holiday factors:

```text
cold_start_prediction = max(0, round(Bc * Dt * Mt * Wt * Ht))
mode = COLD_START
confidence = null
model_version_id = null
label = Low-confidence heuristic estimate
```

Cold start has no numeric confidence setting. UI, DTOs and SQL must retain null rather than converting it into a percentage; model-confidence averages exclude heuristics and show their count separately.

Administrator training creates an inactive candidate. Evaluation uses chronologically later holdout observations unused in fitting or parameter selection; Random Forest and Linear Regression use identical training/test data. Store MAE, RMSE, MAPE, R^2, sample counts, periods and origin composition. Exclude zero actuals only from MAPE; unavailable MAPE/R^2 or an empty comparison are not perfect scores. Activation and restoration require separate explicit administrator actions. NFR-ACC-05 rejects activation if candidate MAE exceeds active-model MAE on the same later test set; failure retains the active model. MAPE <10% and R^2 >0.85 are, at most, optional aspirations, not acceptance gates or achieved results.

## 4. Joint production planning and FEFO

The [inventory plan](inventory_integration/README.md) applies Section 4.9.3 across the full selected-date plan:

1. Build temporary ingredient balances from active, unexpired batches valid for the production date.
2. Subtract recipe requirements of existing confirmed but unprocessed decisions. If commitments already exceed stock, return shortages and require correction.
3. Process unconfirmed active categories in ascending `display_order`. Compute `max_producible = min_i floor(remaining_ingredient_i / recipe_requirement_i)` over required ingredients.
4. Recommend `min(predicted_units_sold, max_producible)`, subtract its requirements from the temporary balance, then process the next category. Missing/invalid recipes block a recommendation.
5. On confirmation/revision, replace that decision's previous quantity and validate it with all other outstanding commitments. Recalculate affected recommendations. Processed decisions are excluded.

Confirmation records the manager's decision/reason and changes no inventory. Recommendations never add a production buffer above predicted sales. A manager may override with a reason only when the combined plan remains feasible.

FEFO excludes inactive/expired/future-received batches and orders valid batches by `expiry_date ASC, received_date ASC, id ASC`. Expiry determines eligibility and consumption order. A newer receipt expiring sooner is consumed before an older receipt expiring later; equal expiry dates use receipt date, then ID.

## 5. Manual operational workflow and atomic simulation

Users open/refresh the application to obtain pending-action indicators. There are no scheduled daily operations or 06:00/18:00 reminder promises. Event alerts and pending indicators never initiate prediction, training, confirmation, simulation or allocation.

The manager manually generates the next-day prediction, reviews jointly feasible recommendations and explicitly confirms quantities. Official simulation defaults to the current date and requires that selected date's stored prediction and confirmed decisions. It cannot use a fallback recommendation or a client-produced override.

[POS plan](pos_simulation/README.md): one Node-owned PostgreSQL transaction/RPC locks the date's decisions, recipes/stock as needed, and valid batches in consistent order; revalidates combined stock while preserving other outstanding commitments; deducts FEFO exactly once before sales processing; and commits batch/snapshot changes, inventory movements, `DailyProduction`, `SalesTransaction`, `DailyResult` and one validated simulation-origin `DailySalesRecord` per category together. Any failure rolls back everything. Unique prediction -> decision -> production -> result links and locked duplicate checks prevent a retried/concurrent request from deducting twice. RPC inputs are authorized server inputs, never trusted client feasibility/actor claims.

Simulation uses the stored contextualised prediction as baseline with configured time-slot/stochastic variation. Weather/holiday/season context remains traceable but is not multiplied again. `units_sold <= produced`; `lost_sales = max(0, demand - produced)`; `estimated_demand = units_sold + lost_sales`; `leftover = produced - units_sold`. Isolated test scenarios are not persisted operational actions. Re-simulation with exact original batch movement/history reversal is future work; there is no current force-refresh or correction-batch recovery path. No `SimulationRun` or `LeftoverRecord` table is added.

## 6. Leftovers, reporting and notifications

Manager-confirmed donation/waste allocations lock the corresponding `DailyResult`, validate positive quantities and the remaining balance, and atomically store the allocation and updated remainder. Donations require an active charity; waste requires a disposal reason. Category is obtained through DailyResult, not duplicated on normalized allocation rows.

```text
leftover = donated + wasted + remaining_unallocated
sales_prediction_error = units_sold - predicted_units_sold
leftover_rate_pct = leftover / produced * 100
revenue = sum(transaction.quantity * transaction.unit_price)
ingredient_cost = sum(consumed_batch_quantity * stored_batch_unit_cost)
gross_profit = revenue - ingredient_cost
gross_profit_margin_pct = gross_profit / revenue * 100
```

Cost uses actual FEFO consumption with batch cost snapshots and consistent units, including ingredients used for unsold production. Master-price changes cannot rewrite history. Transaction unit prices are snapshots. Signed prediction errors and negative profit/margin are valid. Zero-denominator percentages display Not Applicable. Actual discarded waste is separate from donated/unallocated leftovers. Detailed transactions and daily totals are alternate aggregation levels, not additive sources.

Donation workflow uses `PENDING -> COLLECTED -> COMPLETED`; `CANCELLED` is a recognized status whose cancellation/reallocation policy remains an explicit open decision. Status changes have a dedicated endpoint, confirmation and audit. No donation is automatic. See [donation/report plan](donation_dashboard/README.md).

Reports are manually requested by date, daily/weekly/monthly/custom period and category, including seven-day weekly summaries and CSV/PDF exports. `ReportService` supplies the same calculations to UI and exports; CSV retains `data_origin`, PDF displays simulation labels. Reports neither alter operational data nor imply real transactions.

Each notification has `recipient_user_id`, recipient read state, per-type preferences, recipient-owned active FCM tokens and `notification_deliveries`. Foreground Realtime is recipient-only; Node controls writes. Delivery states are `PENDING`, `SUBMITTED`, `DELIVERED`, `FAILED`, `SKIPPED`; submission is not confirmed delivery. Include low stock, expiry, low confidence, lost sales, surplus, donation status and external/system failures. Push failure retains the in-app record. Pending indicators are computed on request, not background schedules.

## 7. Implementation order and planned acceptance

All steps remain future implementation work:

1. Module 0: [database catalogue](../database_canonical_design.md), 29 public tables, managed `auth.users`, one computed view; constraints, DTO field mappings, seeds and recipient Realtime policy.
2. Module 1: authentication/active-profile authorization, administration, audited settings, Repos/adapters and shared contracts; no provider secrets in settings or client code.
3. Module 2: validated origin-prioritized history, features, cold start/confidence, candidate training/evaluation/explicit activation.
4. Module 3: master-data operations, dated inventory, joint recommendations and confirmed decisions.
5. Module 4: atomic FEFO simulation and validated historical handoff, including duplicate/failure behavior.
6. Module 5: Flutter role views, transactional leftovers, status, dashboards and filtered reports/exports.
7. Module 6: recipient event notifications, manual pending indicators and cross-module acceptance checks (planned continuously as each dependency becomes available).

Use [testing plan](operation_reminders_testing/README.md) and [traceability matrix](../planning_documents_change_report.md#requirements-traceability-matrix). Reference environment: Android 10+, >=4 GB RAM, stable >=10 Mbps network, up to 20 active categories, 365 daily records/category and <=50 displayed rows/page. Verify >=95% of specified screen requests within 3 s; prediction/recommendation within 15 s; 12-hour simulation or seven-day report within 30 s. Check 360x640 to 412x915 dp layouts and >=80% independent UAT completion of the five named tasks. No participants or results are asserted.

## 8. Open decisions

The report does not define cancellation/reallocation accounting and status-transition details for cancelled donations. Resolve that business policy before enabling cancellation; no implicit stock release is permitted. First model activation requires a valid reviewed evaluation and explicit administrator confirmation, with no invented incumbent score. For quantity rounding, this plan uses nearest integer with half ties away from zero consistently across languages, a declared engineering convention for the report's round operator. Timed reminders and replacement/re-simulation are future scope, not prerequisites for the current workflow.
