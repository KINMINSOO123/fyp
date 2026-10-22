# Smart Bakery Database Schema Verification Plan

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

**Historical audit snapshot:** 31 July 2026. **Current reconciliation:** 11 October 2026.
**Authority:** latest `RSW_SooKinMin_Project1 (1).docx`, especially Sections 4.5.1-4.5.4, 4.7-4.9 and Chapter 3 BR/FR/NFR tables. The repository [report mirror](RSW_SooKinMin_Project1.docx.md) is a reading aid; the DOCX controls requirements.
**Status:** documentation review and future verification plan; no database functionality or test pass is claimed.

## 1. Evidence and historical status

The July audit found a Flutter starter and planning Markdown, with no implemented Smart Bakery schema, generated database types, Node backend or FastAPI service. Its older table counts and proposed fixes were observations about that historical plan, not a competing specification. This reconciliation replaces their active guidance with the report's Section 4.5 catalogue. Deletion of `FYP Report.md` is retained; no replacement implementation/testing chapters are invented.

The current repository still supplies the starter and plans, not verified backend/ML/database functionality. SQL, types, Repos, policies and RPC names in Markdown remain proposed artifacts. Neither this review nor the historical audit proves any Supabase deployment exists. No package install, migration, application implementation or runtime test is part of this change.

## 2. Catalogue and count checks

The detailed field dictionary, keys and ERD are in [database_canonical_design.md](database_canonical_design.md), Sections 3-11. Derive counts from the following actual catalogue rather than legacy "19 tables" headings:

| Group | Public application tables | Count |
|---|---|---:|
| Access/configuration | `user_profiles`, `bakery_settings`, `system_settings` | 3 |
| Catalogue/inventory | `bread_categories`, `ingredients`, `recipes`, `inventory`, `inventory_batches`, `inventory_log` | 6 |
| Context/history/models/prediction | `weather_records`, `calendar_events`, `daily_sales_records`, `ml_model_versions`, `model_evaluations`, `feature_importance`, `daily_predictions`, `prediction_calendar_events` | 8 |
| Production/POS/surplus | `production_decisions`, `daily_production`, `daily_results`, `sales_transactions`, `charity_partners`, `donations`, `waste_records` | 7 |
| Notifications/audit | `notifications`, `notification_preferences`, `fcm_tokens`, `notification_deliveries`, `system_logs` | 5 |
| **Total public application tables** | | **29** |

Additionally show **one external Supabase-managed `auth.users` table** and **one computed `sales_by_timeslot` view**. The schema has **zero PostgreSQL enum types**: its **21 controlled-value domains** use text CHECK constraints and corresponding application types. View outputs, DTOs, model artifacts, reports, recommendations, `DailyContext`, `SimulationRun` and `LeftoverRecord` are not additional base tables.

The 21 domains are user role, account status, setting data type, data origin, ingredient unit, inventory batch status, inventory movement reason, weather condition, calendar-event type, model type, model lifecycle, evaluation label, prediction mode, production option, sales time slot, donation status, notification severity, notification type, push status, audit outcome and audit severity. Their exact values are maintained in the canonical design Section 3.

## 3. Schema and relationship verification

These checks are to run after implementation; all are currently **PLANNED**.

| Check | Expected persistent contract | Report trace |
|---|---|---|
| Identity | `user_profiles.user_id` references Auth; exactly one BAKERY_MANAGER or SYSTEM_ADMINISTRATOR role and ACTIVE/INACTIVE status; no duplicated credentials | Table 4.15, Section 4.8 |
| Singleton | `bakery_settings.singleton_guard` NOT NULL, TRUE-only, UNIQUE; setup creates one row and administration updates it | Section 4.5.2 |
| Settings | Unique key, validated JSON/data type and updater; no provider secrets in DB/client | Table 4.15, NFR-SEC-05 |
| Recipe | Unique category/ingredient pair; positive grams; configured active catalogue, not four-category/five-ingredient caps | Table 4.16 |
| Batch | Positive initial grams, remainder 0..initial, expiry later than receipt, immutable unit-cost snapshot | Tables 4.16, 4.20 |
| Source identity | SIMULATION_GENERATED requires unique source result and validation; actual/imported require external source reference and no result link | Sections 4.5.3-4.5.4 |
| Observation uniqueness | Unique category/date/origin; one selected validated observation per category/day in actual -> imported -> simulation priority | BR-DP-03-04, Section 4.5.4 |
| Prediction mode | MODEL requires non-null model reference and 0..100 confidence; COLD_START requires both NULL | NFR-ACC-08, Section 4.5.3 |
| Model governance | One ACTIVE RF version/category; candidate/evaluation/activation/restoration separate; retain history and untouched holdout provenance | FR-DP-09-12, NFR-ACC-01-05 |
| Prediction context | Optional weather reference and prediction-calendar junction; no repeated overall context multipliers in simulation | Table 4.17, BR-POS-07 |
| Operational chain | Unique prediction -> decision -> production -> result links; matching category/date through composite keys or equivalent transactional checks | Tables 4.18, 4.20 |
| Transactions/history | Every successful result has sales details and one validated SIMULATION_GENERATED history row; no incomplete commit | Section 4.5.4, FR-POS-08 |
| Allocation normalization | Donation/waste category comes through DailyResult, not duplicated; positive quantity, active charity/disposal reason and confirming manager | Table 4.18 |
| Notification recipient | Recipient FK, per-user/type preference, recipient-owned active tokens, per-device attempts and recipient read state | Table 4.19 |
| Historical integrity | RESTRICT retained links; deactivate master/profile/token records; append-only non-secret audit events | Section 4.5.4, NFR-DAT-03 |

## 4. Required behavioural and failure checks

| ID | Planned scenario | Expected result |
|---|---|---|
| DB-01 | Manager attempts master/settings/users/model mutation; administrator attempts prediction/confirmation/simulation/allocation | Cross-role requests rejected after JWT and ACTIVE-profile validation; no automatic administrator inheritance |
| DB-02 | Invalid JWT, inactive profile, spoofed actor/role/feasibility; two concurrent final-admin removals | Reject unauthorized input; retain at least one active administrator; audit actual actor |
| DB-03 | Insert two bakery settings; invalid role/status/settings JSON or secret field | Reject invalid rows/settings; normal singleton update succeeds |
| DB-04 | 29 distinct valid category days plus duplicate/imported/simulation records for those days | Still 29 observations; actual wins, then imported, then simulation; invalid rows excluded |
| DB-05 | 30 selected valid days but missing/invalid active RF model | COLD_START; history average is Bc; configured base only when no valid observation exists |
| DB-06 | COLD_START confidence 65 or model reference; MODEL null confidence/reference; confidence outside 0..100 | Reject invalid SQL/DTO combinations; cold-start UI displays heuristic Low Confidence and no percentage |
| DB-07 | Confidence tree mean/sigma: (100,0), (100,25), (100,26), (0,0), (0,2) | Formula yields 100,75,74,100,0 respectively; MODEL below 75 is Low Confidence, equality is not; no forced 50-98 range |
| DB-08 | Empty/non-finite tree predictions or invalid configured factors | Validation error/controlled cold-start fallback; do not fabricate confidence or successful MODEL output |
| DB-09 | Chronological holdout used for tuning; different RF/LR datasets; same dates with changed observations | Reject leakage/incomparable evaluation; check manifest/fingerprint/source labels, not dates alone |
| DB-10 | Candidate MAE 8, active MAE 7 on identical later holdout; activation transaction failure | Reject candidate activation, preserve active model and retained evaluations; no immediate activation |
| DB-11 | All actuals zero or constant holdout | Zero actuals remain in MAE/RMSE; MAPE uses only positive actuals and is NULL if none; undefined R^2 is NULL, never silently perfect |
| DB-12 | Two categories each request 8 units, flour 1,000 g, each needs 100 g | Display-order recommendations 8 then 2; no double allocation or automatic buffer |
| DB-13 | Confirmed outstanding 6 units; revise to 4; another category shares flour | Replace 6 with 4, recalculate remaining availability; confirmation changes no stock; processed decisions not reserved again |
| DB-14 | Commitments exceed stock after a stock change; concurrent confirmations | Explain ingredient shortages and reject infeasible plan; joint validation/locking prevents overspending |
| DB-15 | Batch A received 1 Oct, expires 20 Oct; B received 2 Oct, expires 15 Oct; produce 10 Oct | Consume B first because it expires earlier; equal expiry dates use receipt date, then ID; expired/inactive/unreceived batches excluded |
| DB-16 | Official simulation lacks stored selected-date prediction or manager confirmation | Reject; current date default, no recommended-quantity fallback or producedOverride bypass |
| DB-17 | Known contextual prediction, simulation with weather/holiday/season factors | Use stored baseline plus time-slot/stochastic variation; do not multiply those factors again |
| DB-18 | Duplicate or concurrent simulation requests for same decisions | One completed operational chain; duplicate returns 409 ALREADY_SIMULATED with stored-result link and zero second deduction |
| DB-19 | Fail after FEFO, snapshot/log changes, production, sales, result or history insert | Roll back all batch/snapshot/movement/production/sales/result/history changes; no correction-batch recovery |
| DB-20 | Leftover 10, concurrent donation 7 and waste 5 | Lock result; accept only feasible allocation; maintain leftover = donated + wasted + remaining_unallocated |
| DB-21 | Donation inactive charity, nonpositive quantity, waste missing reason; unconfirmed action | Reject; all allocations manager-confirmed and audited; no automatic donation |
| DB-22 | Donation PENDING -> COLLECTED -> COMPLETED and unauthorized status update | Manager-only status endpoint updates history/event; cancellation/reallocation case remains gated by open policy |
| DB-23 | Recipient A authenticates while B receives foreground notification | A sees no B row through Node or Realtime; no direct general SELECT/write privileges; mark-read only affects owned row |
| DB-24 | Disabled/missing push preference, inactive profile/token, other user's token; valid opt-in | SKIPPED with recorded skip_reason for ineligible dispatch; submit only to intended recipient's valid active tokens; preserve per-device attempts |
| DB-25 | Provider accepts message but no delivery callback | SUBMITTED remains distinct from DELIVERED; failure details/attempt timestamps preserved; retry adds attempt |
| DB-26 | Two FEFO batches at MYR 2/kg and MYR 5/kg; consume 1 kg each; change master price afterwards | Ingredient cost stays MYR 7 from immutable consumed-batch snapshots; no recosting using ingredient master |
| DB-27 | Produced 10, sold 6, prediction 8, lost sales 3, donated 2, wasted 1 | Error -2, estimated demand 9, leftover 4, remaining 1, leftover rate 40%; donations/unallocated units not counted as waste |
| DB-28 | Revenue below cost; revenue/production zero | Negative gross profit/margin permitted; zero-denominator percentages Not Applicable; no misleading positive floor |
| DB-29 | UI vs weekly/category/date-filtered CSV/PDF report | Same values and simulation labels; revenue totals not added to detailed transactions again; export cannot mutate source data |
| DB-30 | Open/refresh app with pending next-day prediction/confirmation/simulation | Derived pending indicators only; no scheduled 06:00/18:00 reminder and no automatic operation |

Expiry-day eligibility follows the canonical planning convention: a batch whose expiry date equals production date is usable until that date ends. Receipt-order versus expiry-order verification remains mandatory regardless of this boundary convention.

## 5. Measurable NFR plan

Run measurements only after implementation under the report reference environment: Android 10+, at least 4 GB RAM, stable network at least 10 Mbps, up to 20 active categories, 365 daily records/category and at most 50 displayed records/list page. Record hardware, network, data origins, request samples and measured results rather than asserting a pass from design review.

| Requirement | Planned acceptance measurement |
|---|---|
| NFR-PER-01 | At least 95% of specified login, dashboard, prediction-history, inventory-list, report-list and notification-list requests finish within 3 seconds |
| NFR-PER-02 | Next-day prediction/recommendation for reference workload finishes within 15 seconds |
| NFR-PER-03 | 12-hour POS simulation or seven-day report for reference workload finishes within 30 seconds |
| NFR-USA-03 | Controls/content remain accessible at 360x640 through 412x915 dp; no overlap, clipping or required horizontal scrolling |
| NFR-USA-04 | At least 80% independently complete login, prediction, confirmation, simulation and leftover recording without moderator assistance/task-blocking issue; participant count and results are not invented |
| NFR-SEC-01-05 | Authentication/role tests, no plaintext credential storage, HTTPS TLS 1.2+, protected provider secrets, scoped recipient Realtime exception |
| NFR-REL-01-04 | Transaction fault injection, active-model retention, understandable retry/external-failure behaviour, nonnegative physical quantities |
| NFR-DAT-01-03 | Constraints, unique IDs/timestamps, actor-linked audit; signed error/profit remains valid |
| NFR-ACC-01-08 | Untouched chronological holdout, zero handling, RF/LR comparison, higher-MAE rejection, correct sales target/provenance and confidence checks above |

## 6. Implementation order and review boundary

1. Review the DOCX-derived catalogue/controlled values and unresolved donation cancellation policy.
2. During future implementation, create schema/keys, generated mappings and seed examples; keep secrets outside DB settings.
3. Implement JWT/profile/permission boundary and recipient-only Realtime policy before exposing business endpoints.
4. Implement joint confirmation, FEFO/atomic POS, model lifecycle and transactional allocation before UI can invoke those operations.
5. Implement recipient preference/token/delivery tracking, report calculations and manual CSV/PDF exports.
6. Run the planned schema, role, concurrency, rollback, provenance, cost/export and NFR checks; record actual evidence and failures at that time.

The Markdown review may check catalogue counts, field spellings, balanced diagrams/fences, references and contradiction patterns. These static checks are not executed migrations, API tests, ML evaluations, performance measurements or UAT. The genuine open business decision is cancellation/reallocation accounting and allowed reversible donation transitions; re-simulation remains future work.
