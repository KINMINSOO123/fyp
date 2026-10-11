# Smart Bakery Planning-Document Consistency Change Report

**Revision date:** 29 July 2026  
**Scope:** Planning and report Markdown only  
**Implementation status:** Proposed design; not implementation-verified  
**Source-code status:** No Dart, TypeScript, JavaScript, Python or SQL source file was created or modified  
**Diagram status:** No class diagram was drawn

## 1. Outcome

The affected Smart Bakery planning documents were reconciled with the revised Chapter 3 requirements and the canonical Logical View. The design now uses these settled rules consistently:

- `DailySalesRecord.unitsSold` is the ML target, and `DataOrigin` is exactly `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL` or `SIMULATION_GENERATED`.
- `DailyResult` is the detailed POS outcome, not the historical ML dataset. A successfully completed simulation creates a validated simulation-origin `DailySalesRecord`.
- A System Administrator manually requests training. Training creates a candidate; chronological evaluation precedes explicit activation, and a previous valid model can be restored.
- FastAPI has no Supabase client or application Repo. Node.js/Express owns database access through TypeScript `Repo` classes and calls FastAPI only through `FastApiMlClient`.
- POS simulation uses the stored `DailyPrediction` as its baseline, deducts FIFO stock once before sales, and reverses or rolls back that deduction if later processing fails.
- Donation and waste are recommendations until a Bakery Manager confirms them. Confirmed donation plus waste cannot exceed leftover stock.
- Weekly reporting supports PDF and CSV, while access management, settings, audit logs, notifications, device tokens and FCM remain in scope.

Older implementation sketches retained for planning history are labelled **historical**, **retired** or **superseded** and are not authoritative implementation instructions.

## 2. Files changed and affected sections

| File | Sections updated | Main consistency changes |
|---|---|---|
| `FYP Report.md` | Chapters 1, 3 and 4; requirements, use cases, architectural design and Logical View | Revised functional requirements, roles, ML lifecycle, data-origin rules, POS transaction rules, leftover allocation, reporting, database ownership and proposed classifier catalogue |
| `logical_view_canonical_design.md` | Whole canonical specification | Added/clarified proposed Views, Controllers, Services, Repos, adapters, domain models, DTOs, Python ML services, multiplicities, diagram membership and forbidden dependencies |
| `logical_view_class_diagram_plan.md` | Document status and canonical supersession notice | Preserved the earlier audit as historical evidence while directing all final design choices to the canonical specification |
| `Final Year Project/ARCHITECTURE.md` | Architecture principles, layer rules, directory plans, integration paths and module conformance | Made Node the sole Supabase owner; removed Python repository ownership; established class-based TypeScript layers, thin route modules and `FastApiMlClient` |
| `Final Year Project/structure_chart.md` | Prediction, simulation, leftover, reporting, administration and notification branches | Added administrator model lifecycle, daily-sales origin, waste confirmation and exports; changed foreground notification delivery to the Node boundary |
| `Final Year Project/fyp_food_waste.md` | Authoritative revision notice; financial/ML separation; simulation and training-target alternatives; workflows | Marked conflicting early examples as retired; established `unitsSold`, stored-prediction simulation, manual allocation and Node-only database access |
| `Final Year Project/data_foundation/MODULE.md` | Module responsibilities, schema catalogue, seed rules, integration and resolved decisions | Added `daily_sales_records`, `model_evaluations` and `waste_records`; clarified model lifecycle, settings, origin-aware seed data and Node-controlled notifications |
| `Final Year Project/data_foundation/README.md` | Revision baseline, proposed schema, RLS, seed and Python-contract sections | Added canonical tables/fields and removed general direct-client CRUD assumptions; documented FastAPI DTO-only data access |
| `Final Year Project/nodejs_middleware/MODULE.md` | Layer ownership, proposed artifacts, API responsibilities and integration rules | Specified class Controllers/Services/Repos/adapters, model-management endpoints, reporting, waste and support modules |
| `Final Year Project/nodejs_middleware/README.md` | Revision baseline, proposed structure and canonical service boundaries | Added required orchestration/adapters and labelled incompatible router/function sketches as superseded |
| `Final Year Project/ml_prediction/MODULE.md` | Whole ML boundary, workflows, metrics, service catalogue and endpoint contracts | Removed Supabase/Python Repo ownership; added candidate lifecycle, origin-labelled evaluation, cold start, confidence and artifact services |
| `Final Year Project/ml_prediction/README.md` | Revision baseline, canonical flow, artifact list and historical-sketch notices | Replaced the authoritative direct-database plan with DTO-based FastAPI service contracts and marked old code sketches as non-implementable history |
| `Final Year Project/inventory_integration/MODULE.md` | Responsibilities, resolved decisions, recommendation and notification flows | Requires stored `DailyPrediction`, forbids prediction regeneration, keeps decision confirmation separate from deduction and routes alerts through Node |
| `Final Year Project/inventory_integration/README.md` | Revision baseline, artifacts and canonical recommendation flow | Added the stored-prediction/no-ML-fallback rule and marked incompatible sketches as superseded |
| `Final Year Project/pos_simulation/MODULE.md` | Responsibilities, resolved decisions, service workflow, persistence and tests | Established stored baseline, context traceability, pre-sales FIFO deduction, rollback, detailed result persistence and sales-history creation |
| `Final Year Project/pos_simulation/README.md` | Revision baseline, proposed artifacts and canonical transaction flow | Added `PosSimulationController`, `PosSimulationService` and `TransactionRecordingService`; labelled older double-context/deduction-after-sales sketches as superseded |
| `Final Year Project/donation_dashboard/MODULE.md` | Responsibilities, resolved decisions, workflows, data access, API and reporting | Added manager-confirmed donation/waste, category-specific `WasteRecord`, unallocated leftover and PDF/CSV reporting |
| `Final Year Project/donation_dashboard/README.md` | Revision baseline, artifacts, canonical allocation rules and historical-sketch notices | Retired automatic donation and direct Flutter database subscription plans while retaining charity/status planning |
| `Final Year Project/operation_reminders_testing/MODULE.md` | Administration, reminders, test coverage and module dependencies | Added candidate lifecycle, origin/metric tests, simulation rollback, allocation constraints, exports and preserved support modules |
| `Final Year Project/operation_reminders_testing/README.md` | Revision baseline, scope and verification plan | Aligned reminders/tests with manual administrator/manager actions and the revised architecture |
| `planning_documents_change_report.md` | New document | Records the affected files, resolved inconsistencies, impacted design artifacts and remaining open issues |

No unrelated root-level generated overview was changed.

## 3. Inconsistencies found and resolution

| Inconsistency found | Resolution |
|---|---|
| `DailyResult` and simulated result rows were sometimes treated as the ML training source | Introduced `DailySalesRecord` as the validated historical record; `DailyResult` remains the detailed POS outcome |
| `sold`, `estimatedDemand` and demand were competing ML targets | Standardised the target as `DailySalesRecord.unitsSold`; `lostSales` and `estimatedDemand` are analysis only |
| Historical and simulated data had no canonical provenance | Added the exact `DataOrigin` enumeration and origin-labelled evaluation results |
| Simulation evaluation could be interpreted as real accuracy | Required an explicit simulation-based label and prohibited presenting it as real-world accuracy |
| Retraining was automatic or immediately activated a model in some plans | Made training administrator-initiated, candidate-only, evaluated before explicit activation, with restoration of a previous valid version |
| Evaluation split and metric handling were incomplete | Required chronological holdout, MAE, RMSE, MAPE and R²; zero actuals are excluded only from MAPE |
| Cold-start logic and confidence logic were mixed into prediction code | Added separate `ColdStartService` and `ConfidenceService`; retained configurable values and left the final confidence formula unresolved |
| POS simulation reapplied weather/holiday effects already present in the prediction | Made stored `DailyPrediction` the baseline and context traceability-only during simulation |
| Inventory was deducted after sales or failure handling was incomplete | Required FIFO deduction exactly once before sales and rollback/reversal after any later failure |
| Simulation persistence omitted a canonical training-history handoff | Required production, transactions, lost sales, leftovers and `DailyResult`, followed by a validated simulation-origin `DailySalesRecord` |
| Leftovers implied automatic donation and had no explicit disposal record | Added recommendation-only behaviour, Bakery Manager confirmation, category-specific `WasteRecord` and an unallocated-leftover balance |
| Donation quantities and waste quantities were not jointly constrained | Added `donated + wasted <= leftover` per result/category |
| Reports were dashboard-only or had no export boundary | Added weekly report generation and PDF/CSV export through `ReportService` and `ReportExportAdapter` |
| FastAPI and Flutter plans included direct Supabase table access | Made Node.js/Express the sole PostgreSQL owner; Flutter uses the authenticated backend boundary and FastAPI receives validated DTOs |
| Express routers and FastAPI routes were represented as business classifiers | Classified them as thin modules/functions and excluded them from UML class diagrams |
| TypeScript logic mixed functions, Controllers, Services and repositories | Standardised proposed TypeScript application elements as constructor-injected classes with `Controller -> Service -> Repo/Adapter` |
| Names drifted between `DemandPrediction`, `DailyPrediction`, `Repository`, `Repo`, screen/page and View | Standardised `DailyPrediction`, `Repo`/`BaseRepo<T>` and the `View` suffix |
| Prediction orchestration and the FastAPI boundary were missing | Added proposed `PredictionOrchestrationService` and `FastApiMlClient` |
| Foreground notifications bypassed the Node data boundary | Kept FCM for background push and routed foreground reads/events through an authenticated Node API, polling, SSE or WebSocket relay |

## 4. Planned database tables affected

These are proposed database-design effects, not applied migrations.

| Planned table | Effect of revision |
|---|---|
| `daily_sales_records` | Canonical validated ML history with date, category, `units_sold`, `data_origin`, validation status and optional source reference |
| `daily_results` | Detailed POS result only; includes predicted, produced, units sold, lost sales, estimated demand, leftover and remaining unallocated leftover |
| `daily_predictions` | Uses the canonical daily-prediction name and predicted-units-sold semantics; supplies the stored POS baseline |
| `daily_production` | Records actual completed production associated with the manager's production decision |
| `sales_transactions` | Stores detailed simulated sales before daily aggregation |
| `production_decisions` | Preserves the manager-confirmed quantity and traceability to the relevant prediction |
| `inventory_batches` and `inventory_log` | Support FIFO deduction exactly once plus compensating reversal/rollback traceability |
| `donations` | Records category-specific manager-confirmed donation allocations and status |
| `waste_records` | New/clarified category-specific disposal record with quantity, reason and confirming manager |
| `ml_model_versions` | Supports candidate, active and inactive/restorable lifecycle states and artifact references |
| `model_evaluations` | Stores chronological, origin-labelled MAE/RMSE/MAPE/R² results and relevant sample counts |
| `feature_importance` | Stores feature importance returned for a trained candidate/model version |
| `weather_records` and `calendar_events` | Remain Node-owned contextual caches supplied to FastAPI through DTOs |
| `users`, role/access tables, `bakery_settings`, `system_settings`, `system_logs`, `notifications` and `fcm_tokens` | Explicitly preserved; not removed merely because they are outside the focused class diagrams |

## 5. API and shared-contract effects

### Express application contracts

| Area | Planned contract effect |
|---|---|
| Prediction | Generate/read `DailyPrediction` through `PredictionOrchestrationService`; missing stored predictions are not regenerated by unrelated modules |
| Model management | Administrator-only train, evaluate, activate, restore and active-model status operations |
| POS simulation | Manager-initiated simulation with date/options, result retrieval and transaction retrieval; operation must be idempotent/transaction-safe once specified |
| Leftover allocation | Read allocation, request recommendation, confirm donation, confirm waste and update donation status |
| Weekly reporting | Retrieve weekly report and export it as PDF or CSV |
| Notifications | Authenticated foreground retrieval/event relay plus FCM-backed background delivery |

### Node.js–FastAPI DTOs

| DTO or enum | Main revision |
|---|---|
| `DataOrigin` | Exact values `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, `SIMULATION_GENERATED` |
| `PredictionCategoryInput` | Validated sales history, target date, context and cold-start configuration |
| `PredictionRequest` / `PredictionResponse` | Category prediction inputs and units-sold results with confidence/mode/model traceability |
| `TrainingObservation` | Date, category, `unitsSold`, `dataOrigin` and associated context |
| `TrainingRequest` / `TrainingResult` | Administrator-triggered candidate training input and returned artifacts/metrics/importance |
| `EvaluationRequest` / `EvaluationResult` | Specified model artifacts plus chronologically later holdout observations; no activation side effect |
| `ModelMetrics` | MAE, RMSE, MAPE, R², total sample count, MAPE sample count, origins and evaluation label |

The exact JSON/OpenAPI shapes remain proposed and require versioning before implementation.

## 6. Planned classifiers affected

| Layer | Added, renamed or materially clarified classifiers |
|---|---|
| Flutter presentation | `PredictionView`, `ModelManagementView`, `InventoryView`, `PosSimulationView`, `LeftoverManagementView`, `DashboardView` |
| Flutter integration | `ApiClient` |
| TypeScript Controllers | `PredictionController`, `ModelManagementController`, `RecommendationController`, `InventoryController`, `PosSimulationController`, `LeftoverManagementController`, `ReportController`, `DashboardController` |
| TypeScript Services | `PredictionOrchestrationService`, `ModelManagementService`, `RecommendationEngine`, `InventoryService`, `ProductionDecisionService`, `PosSimulationService`, `TransactionRecordingService`, `LeftoverManagementService`, `DashboardService`, `ReportService`, `ContextService` |
| TypeScript Repos | `BaseRepo<T>`, `DailySalesRecordRepo`, `DailyPredictionRepo`, `DailyResultRepo`, operational Repos, donation/waste Repos, context Repos and model-lifecycle Repos |
| External adapters | `FastApiMlClient`, `OpenWeatherMapClient`, `NagerDateClient`, `ReportExportAdapter`, plus the preserved FCM adapter boundary |
| Domain and DTO | `DataOrigin`, `DailySalesRecord`, `DailyPrediction`, `DailyProduction`, `SalesTransaction`, `DailyResult`, `Donation`, `WasteRecord`, `ModelVersion`, `ModelEvaluation`, shared ML DTOs |
| Python/FastAPI ML | `PredictionService`, `FeaturePreparationService`, `ModelTrainingService`, `ModelEvaluationService`, `ColdStartService`, `ConfidenceService`, `CategoryPredictor`, `ModelArtifactStore` |

`SimulationRun` and `LeftoverRecord` remain excluded. Express router modules, FastAPI endpoint functions, starter/private Flutter classes, small widgets, utilities and framework classifiers remain excluded from the Logical View.

## 7. Remaining unresolved issues

| Unresolved issue | Why it remains open |
|---|---|
| Exact JSON/OpenAPI schemas, field casing, validation errors and contract versioning | The architecture is settled, but no implementation contract source has been selected |
| Final confidence formula and calibration | Random Forest tree variance/model agreement is the planned basis, but evidence is needed before approving a mathematical mapping |
| Definition of a “suitable” historical record beyond validation, chronology and origin | Missing-data, outlier and minimum-context acceptance rules still need agreement |
| Mixed-origin evaluation presentation | Every evaluation is origin-labelled and simulation accuracy cannot be called real-world accuracy, but the final UI wording for mixed datasets is not specified |
| R² behaviour for an insufficient/constant holdout and MAPE when all actuals are zero | Metric edge-case display/API conventions are not yet specified |
| Model artifact storage, retention, backup and activation coordination | The ownership boundary is settled, but the deployment/storage mechanism is not |
| POS idempotency, re-simulation policy and multi-Repo transaction implementation | Rollback/reversal is required, but the exact transaction key and retry/recovery mechanism need design |
| Foreground notification transport | The Node boundary is settled; polling, SSE or WebSocket remains a deployment choice |
| Historical import/actual-POS ingestion contract | `DataOrigin` and the target record are settled, but import formats, validation workflow and source-reference semantics need detail |
| PDF/CSV rendering library, report layout and exact export coverage | Weekly export is required, but provider/library and presentation templates remain open |

