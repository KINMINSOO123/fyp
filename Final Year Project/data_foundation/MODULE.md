# Module 0: Data Foundation and Supabase Schema

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

**Technical build module:** 0; first foundation dependency for modules 1-6.
**Status:** reconciled design, 11 October 2026; proposed database, contracts and checks, not implemented functionality.
**Authority:** latest `RSW_SooKinMin_Project1 (1).docx`, Sections 1.3-1.4, 3.3-3.5, 4.2, 4.5, 4.7-4.9. Read with the [report mirror](../../RSW_SooKinMin_Project1.docx.md), [canonical schema](../../database_canonical_design.md) and [verification plan](../../database_schema_verification.md).

## 1. Purpose, scope and functional mapping

Define shared persistence, domain mappings and constraints for the four objectives: next-day prediction, inventory-aware recommendations, POS simulation, and leftover/donation management. One bakery on Android is in scope. Customer ordering/payment, delivery/marketplace, real POS hardware, multi-branch operation and automatic background scheduling are excluded. Four bread categories and five ingredients are sample seed data; support the configured active catalogue and the reference workload of up to 20 categories.

Technical build numbers 0-6 describe delivery dependencies; they are not replacements for the eight functional modules of Section 1.4.2:

| Functional module | Module 0 contribution | Main consuming technical modules |
|---|---|---|
| 1. User and Access Management | Profiles, single role, account status, Auth identity references | 1 middleware; 6 checks |
| 2. Demand Prediction | History/provenance, context, prediction and model/evaluation metadata | 1 middleware; 2 ML |
| 3. Inventory and Smart Production Recommendation | Categories, ingredients, recipes, batches, movements, decisions | 1 middleware; 3 inventory |
| 4. POS and Sales Simulation | Unique decision/production/result graph, sale snapshots, simulation history | 4 POS |
| 5. Leftover, Donation and Waste Management | Normalized charity/allocation records and result balance | 5 donation/dashboard |
| 6. Reporting and Dashboard | Source records, derived calculation contracts and view | 5 donation/dashboard |
| 7. Alerts and Notifications | Recipient events, preferences, device tokens, delivery attempts | 1 middleware; 6 operations/testing |
| 8. System Administration | Singleton bakery settings, validated nonsecret system settings, roles/audit/model metadata | 1 middleware; 2 ML; 6 checks |

## 2. Persistence catalogue and type conventions

The full field dictionary is [canonical schema Sections 3-7](../../database_canonical_design.md). Do not maintain a contradictory smaller migration sketch.

| Group | Application tables | Count |
|---|---|---:|
| Access/configuration | `user_profiles`, `bakery_settings`, `system_settings` | 3 |
| Catalogue/inventory | `bread_categories`, `ingredients`, `recipes`, `inventory`, `inventory_batches`, `inventory_log` | 6 |
| Context/history/models | `weather_records`, `calendar_events`, `daily_sales_records`, `ml_model_versions`, `model_evaluations`, `feature_importance`, `daily_predictions`, `prediction_calendar_events` | 8 |
| Operations/surplus | `production_decisions`, `daily_production`, `daily_results`, `sales_transactions`, `charity_partners`, `donations`, `waste_records` | 7 |
| Notifications/audit | `notifications`, `notification_preferences`, `fcm_tokens`, `notification_deliveries`, `system_logs` | 5 |
| **Total** | **Public application tables** | **29** |

Also reference one external Supabase `auth.users` table and one computed `sales_by_timeslot` view. There are **0 PostgreSQL enum types**, with **21 text CHECK controlled domains** as enumerated in the canonical document. TypeScript unions, Pydantic literals and Dart mappings reflect those same values; they are not extra database tables/types. Recommendations, `DailyContext`, DTOs, model files, report/export files, `SimulationRun` and `LeftoverRecord` are not base tables.

Use UUID identity keys; profile key is the Auth UUID, and notification preferences/prediction-calendar junctions have composite keys. Quantities use whole integer bread units or numeric grams; monetary snapshots use decimal numeric values. Dates are bakery-local business dates and event timestamps are `timestamptz`. Database snake_case maps explicitly to domain camelCase; preserve uppercase controlled values.

| Contract | Exact values/mapping |
|---|---|
| Role/account | `BAKERY_MANAGER` or `SYSTEM_ADMINISTRATOR`, exactly one; `ACTIVE` or `INACTIVE` |
| DataOrigin | `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, `SIMULATION_GENERATED` |
| Prediction mode | `MODEL`, `COLD_START` |
| Model lifecycle | `CANDIDATE`, `ACTIVE`, `INACTIVE`, `REJECTED` |
| Production option | `ACCEPT_RECOMMENDATION`, `REDUCE`, `MANUAL_OVERRIDE` |
| Donation status | `PENDING`, `COLLECTED`, `COMPLETED`, `CANCELLED` |
| Push delivery | `PENDING`, `SUBMITTED`, `DELIVERED`, `FAILED`, `SKIPPED` |
| Confidence | `daily_predictions.confidence` -> `confidence: number \| null`; required numeric only for MODEL |
| Target | `daily_sales_records.units_sold` -> `DailySalesRecord.unitsSold`; estimatedDemand remains analytical |
| Error | `daily_results.sales_prediction_error` -> `salesPredictionError = unitsSold - predictedUnitsSold` |

## 3. Layer and access contracts

Flutter protected business requests go to TypeScript/Express Controllers -> Services -> Repos -> PostgreSQL. External adapters serve weather/calendar, Auth administration, ML and FCM. Express route modules register Controllers; they are not additional UML classes. `FastApiMlClient` supplies validated DTOs to thin FastAPI routes and Python ML Services. FastAPI has no database client, Supabase URL/key or credentials.

Flutter may directly use Supabase Authentication, recipient-scoped Supabase Realtime foreground notification events and FCM background notifications (Sections 4.2.4, 4.8). Ordinary application-table CRUD, notification preference/token changes and mark-read use Node. Enable RLS for every public table. The only authenticated application-table SELECT exception is eligible notifications for the authenticated ACTIVE recipient; no general CRUD policies. A read-only restricted helper may check the recipient's active profile/type preference without exposing profiles or preferences directly. Test this policy independently of the Node checks.

JWT validation and ACTIVE profile lookup precede role checks. Client actor/role/feasibility fields and email-derived roles are never authoritative. Administrator accounts do not inherit manager-only operations. Preserve the final active administrator; store no passwords/provider secrets in application tables or client code.

| Planned interface | Controller -> Service -> Repo/adapter | Role and View |
|---|---|---|
| `GET/PATCH /api/profile` | ProfileController -> ProfileService -> UserProfileRepo | Both roles, own ProfileView |
| `GET/POST /api/admin/users`, `PATCH /api/admin/users/:id` | UserAdministrationController -> UserAdministrationService -> UserProfileRepo / AuthAdminAdapter | Administrator UserAdministrationView; one role/status; audit |
| `GET/PATCH /api/admin/settings` | SettingsController -> SettingsService -> BakerySettingsRepo / SystemSettingsRepo | Administrator SettingsView; singleton/nonsecret settings only |
| `GET /api/admin/audit` | AuditController -> AuditService -> SystemLogRepo | Administrator AuditView; immutable audit |
| `/api/admin/ingredients`, `/api/admin/batches`, `/api/admin/categories`, `/api/admin/recipes` | InventoryController / RecipeController -> InventoryService / RecipeService -> catalogue/inventory Repos | Administrator InventoryView / RecipeView |
| `/api/admin/charity-partners` | CharityPartnerController -> CharityPartnerService -> CharityPartnerRepo | Administrator CharityPartnersView |
| `/api/admin/models/...` | ModelManagementController -> ModelManagementService -> MlModelVersionRepo / ModelEvaluationRepo / FastApiMlClient | Administrator ModelManagementView |
| Prediction, confirmation, simulation, allocation/status endpoints | Respective operational Controllers/Services -> corresponding Repos | Bakery Manager only |
| Reports/dashboard and personal notifications | ReportService/ReportRepo; NotificationService/recipient Repos | Both roles within permitted scope |

## 4. Data and algorithm invariants

### Prediction and model history

Select one validated observation per category/day in actual -> imported -> simulation priority, including the count for the 30-day threshold. Simulation rows reference their unique source DailyResult; actual/imported rows retain external source references. Train and compare prediction performance on unitsSold; never estimatedDemand.

Use MODEL only with at least 30 distinct selected valid daily observations and a valid active RF model. `ConfidenceService` computes tree mean `mu`, standard deviation `sigma`, `predicted_units_sold = max(0, round(mu))`, and `confidence = 100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))`. Numerical confidence means tree agreement, not an accuracy probability; below configured 75% initial threshold is Low Confidence.

Otherwise use COLD_START: `Bc` is the mean of available valid units-sold observations or configured category base only if there are no valid observations. Apply configured weekday/monsoon/weather/holiday factors: `max(0, round(Bc * Dt * Mt * Wt * Ht))`. Store null confidence and null model_version_id and show a low-confidence heuristic label; never a fixed/configurable numerical cold-start score.

Administrator training creates candidates. Evaluate RF/LR using identical train/test data with a chronologically later holdout excluded from fitting and parameter selection. Retain MAE/RMSE/MAPE/R^2 and origin labels; zero actuals are excluded only from MAPE. Undefined metrics remain null with explanatory labels. Activation is explicit and transactional; reject candidate MAE higher than active MAE on the same holdout, retaining current active model on failure. Restore is separate. Holdout manifest/fingerprint metadata supports proving dataset identity. Optional MAPE < 10% / R^2 > 0.85 are aspirational, not mandatory passes or results.

### Shared ingredients, FEFO and official simulation

Build a temporary balance of date-valid active received batches; reserve all confirmed but unprocessed decisions first. Report infeasible commitments. Allocate remaining unconfirmed categories in ascending display_order, calculate minimum whole-unit capacity across recipe ingredients, recommend min(prediction, capacity), and subtract each recommendation before the next category. Confirmation/revision validates the combined outstanding plan, replaces the old quantity on revision and recalculates affected recommendations. Confirmation does not deduct stock. No automatic buffer exceeds predicted sales; feasible overrides require a reason.

FEFO excludes expired/inactive/unreceived batches then consumes ascending expiry_date, received_date, id. Equal expiry dates use receipt date, then ID as deterministic tie-breakers. A decision with an existing daily_production is processed and cannot be reserved/deducted again.

Official POS uses the current date by default and requires stored prediction plus explicit manager confirmation for the selected date. `PosSimulationService`/`TransactionRecordingService` through `SimulationCommitRepo` plan one Node-owned PostgreSQL transaction with row locking. Revalidate joint outstanding commitments; deduct selected decisions FEFO exactly once before sales processing; commit batch/snapshot/movement changes, production, transactions, DailyResult and one validated SIMULATION_GENERATED history record/category together. All failures roll back. Stored contextual prediction is the baseline with time-slot/stochastic variation, never context multiplication again. Duplicate requests return `409 ALREADY_SIMULATED` with a stored-result link and do not deduct again. No unconfirmed producedOverride or correction-batch substitute exists; re-simulation is future work pending an atomic exact-batch and linked-history policy.

### Results, cost, allocations and notifications

Unique prediction -> decision -> production -> result links retain matching date/category. Results verify estimatedDemand = unitsSold + lostSales; leftover = produced - unitsSold; salesPredictionError = unitsSold - prediction. Leftover percentage is leftover/produced * 100 and differs from actual discarded waste.

Actual consumed FEFO batches supply immutable cost snapshots. The canonical storage convention normalizes batch.unit_cost to MYR/kg at receipt; cost is sum(abs(deduction.change_grams)/1000 * batch.unit_cost), not current ingredient master price. Transaction unit_price is likewise immutable; revenue = sum(quantity * unit_price), gross profit = revenue-cost, gross-profit margin = profit/revenue * 100. Signed errors and negative profit/margin are valid; zero-denominator percentages display Not Applicable. Reports/CSV/PDF share calculations, show simulation origin and avoid double-counting transaction details with daily totals.

Allocation locks DailyResult, requires manager confirmation, positive quantity and active charity or disposal reason, and preserves leftover = donated + wasted + remaining_unallocated. Donation/waste category is derived through DailyResult. Plan status update endpoint `PATCH /api/donations/:id/status`; PENDING/COLLECTED/COMPLETED replace RECORDED/PICKED_UP/DELIVERED. CANCELLED is recognized, but cancellation/reallocation accounting and reversible transitions remain open; no implicit freeing of leftover quantities.

Notifications are recipient-based. Per-type preferences and valid active tokens owned by the intended recipient govern delivery; missing push preference is not opt-in. Persist PENDING/SUBMITTED/DELIVERED/FAILED/SKIPPED attempts with nonblank skip_reason only for SKIPPED; provider submission is not delivery. Include expiry, stock, low-confidence, lost-sales, surplus, donation-status and model/external/system failures. No global read state or all-staff broadcast. Pending-action indicators are derived on open/refresh/state requests, with no automatic prediction/training/confirmation/simulation/allocation or daily timed reminders.

## 5. Implementation order and planned verification

1. Agree catalogue/field mappings/controlled values and the genuinely open donation cancellation semantics.
2. Implement schema, keys, indexes and seed examples during the implementation phase; link retained history with restricted deletion and singleton constraints.
3. Add generated TypeScript/Dart mappings and Node/FastAPI DTO validation, including discriminated nullable prediction mode.
4. Implement Auth/profile/roles, final-admin protection, Repos, narrow recipient Realtime policy and append-only audit.
5. Implement joint confirmation, expiry-ordered FEFO, atomic POS and leftover allocation; model candidate/evaluation/activation rules remain separate.
6. Add notification preference/token/delivery contracts and consistent report/export calculations.
7. Run [database verification plan](../../database_schema_verification.md) after implementation; none of these tests are claimed complete.

Required checks cover cross-role denial, inactive profiles, final-admin concurrency, origin priority/deduplication, 29/30-day boundaries, null cold confidence and formula boundaries, higher-MAE rejection, shared commitments/revisions, FEFO vs FIFO, duplicate simulation, every atomic rollback stage, concurrent allocation, recipient isolation/opt-in delivery, immutable FEFO cost snapshots and UI/CSV/PDF totals.

Under Android 10+, >=4 GB RAM, stable >=10 Mbps, up to 20 categories, 365 records/category and 50 list rows: plan >=95% specified screen requests within 3 seconds; prediction/recommendation within 15 seconds; 12-hour simulation or seven-day report within 30 seconds. Include 360x640-412x915 dp UI checks and >=80% independent UAT task completion; no participant count/results are invented.

## 6. Planned artifacts

Future deliverables are a migration/schema, generated mappings, Repo contracts, transaction bodies, controlled settings validation and representative seed data. They are not implemented files today. No installation, migration or deployment is authorized by this Markdown reconciliation. Build module README examples are design sketches and must continue matching the canonical dictionary and report.
