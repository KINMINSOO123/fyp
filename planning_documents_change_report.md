# Smart Bakery planning-document reconciliation report

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

**Historical reconciliation:** started 2026-10-11; final review 2026-10-12. **Historical change-report snapshot:** 29 July 2026; historical database design/audit: 31 July 2026. Those dates describe earlier planning work, not completion or approval of the current design.

## Source, scope and implementation status

The source read for this reconciliation was the latest available `RSW_SooKinMin_Project1 (1).docx` in the user's Downloads directory. The unnumbered DOCX has identical extracted report text except for trailing blank paragraphs; the newer copy supplies the source images. The repository's [RSW_SooKinMin_Project1.docx.md](RSW_SooKinMin_Project1.docx.md) is the report navigation mirror. The DOCX controls over that mirror and all older planning documents.

Read the report's objectives and scope (Sections 1.1 and 1.4), business rules and requirement tables (3.4.4-3.6), layered interactions/security (4.2.4 and 4.8/Table 4.27), schema tables and constraints (4.5.1-4.5.4), reports/exports (4.7), and algorithms (4.9.2-4.9.3). Visually inspected the DOCX's embedded mean, rounded prediction, confidence, cold-start and maximum-producible equations; text extraction alone omits these equations.

`FYP Report.md` was already deleted by the user when work began. Its deletion is preserved; it is not recreated as a competing specification. The report mirror was already untracked and remains unchanged. Only project-planning Markdown is edited; the Flutter/platform documentation, application code, dependency manifests and DOCX are untouched. No packages, migrations or deployments were performed.

The repository has a Flutter counter starter and plans. All described database schemas, DTOs, APIs, Python/Node classes, algorithms, UI and tests are **proposed**, not implemented or execution-verified. No completed implementation/evaluation chapters, UAT participants, accuracy improvements or test results are invented.

## Planning files covered by the October reconciliation and current design

| Files | Actual reconciliation |
|---|---|
| [Project plan](Final%20Year%20Project/fyp_food_waste.md) | Replaced contradictory concept examples with report-aligned objectives, scope, algorithms, manual workflow, reporting and build order |
| [Architecture](Final%20Year%20Project/ARCHITECTURE.md) | Corrected platform exceptions, MVC boundaries, role/administration contracts and atomic operations |
| [Structure chart](Final%20Year%20Project/structure_chart.md) | Preserved eight functional modules and mapped technical modules 0-6; corrected operational/dependency flow |
| [Data Foundation MODULE](Final%20Year%20Project/data_foundation/MODULE.md) and [README](Final%20Year%20Project/data_foundation/README.md) | Reconciled catalogue, constraints, controlled values, seeds, RLS, DTOs and schema verification order |
| [Node Middleware MODULE](Final%20Year%20Project/nodejs_middleware/MODULE.md) and [README](Final%20Year%20Project/nodejs_middleware/README.md) | Concrete access/profile/role/settings/audit contracts; validated DTOs; recipient Realtime/FCM; manual pending state |
| [ML Prediction MODULE](Final%20Year%20Project/ml_prediction/MODULE.md) and [README](Final%20Year%20Project/ml_prediction/README.md) | Exact confidence/cold-start formulas, null-safe cross-language contracts, origin selection, chronological evaluation and candidate lifecycle |
| [Inventory Integration MODULE](Final%20Year%20Project/inventory_integration/MODULE.md) and [README](Final%20Year%20Project/inventory_integration/README.md) | Shared ingredient commitments, display-order recommendation, replacement confirmation, expiry-order FEFO and cost snapshots |
| [POS Simulation MODULE](Final%20Year%20Project/pos_simulation/MODULE.md) and [README](Final%20Year%20Project/pos_simulation/README.md) | Required stored prediction/confirmation, single transaction/RPC, duplicate protection and complete rollback |
| [Donation Dashboard MODULE](Final%20Year%20Project/donation_dashboard/MODULE.md) and [README](Final%20Year%20Project/donation_dashboard/README.md) | Manual transactional allocation, normalized status workflow, role UI and filtered CSV/PDF reports |
| [Operation Reminders/Testing MODULE](Final%20Year%20Project/operation_reminders_testing/MODULE.md) and [README](Final%20Year%20Project/operation_reminders_testing/README.md) | Request-derived indicators, event notifications, measurable NFR and behavioral verification plans |
| [Database canonical design](database_canonical_design.md) | Report Section 4.5 catalogue/constraints, corrected quantities, nullable confidence, costs, Realtime policy and transaction sketches |
| [Database verification](database_schema_verification.md) | Preserved 31 July audit as history and added current design-review/verification expectations |
| [Logical canonical design](logical_view_canonical_design.md) | Updated class catalogue, two Mermaid class diagrams, domain multiplicities, permissions and endpoint map |
| [Logical diagram plan](logical_view_class_diagram_plan.md) | Retained truthful starter audit, removed obsolete diagram instructions, added current diagram checks |
| [This change report](planning_documents_change_report.md) | Actual changes, source references, complete requirement traceability, validation and open decisions |

The October 11-12 reconciliation edited 22 planning files: three overview documents, fourteen module documents and five root design/audit/change documents. The already deleted report and unchanged report mirror are separately accounted for, not counted as new edits.

## Discrepancies corrected and report references

| Area | Reconciled design | Report basis |
|---|---|---|
| Scope/module numbering | Four objectives; eight functional modules mapped to seven build modules; one bakery/Android; seeds are examples; configured active categories | 1.1, 1.4.1-1.4.3; reference environment in 3.6 |
| Platform boundaries | Protected CRUD via Node Controllers/Services/Repos; Flutter Auth, recipient Realtime and FCM exceptions; no Python database access | 4.2.4, 4.4, 4.8 |
| Confidence | Exact tree mean/deviation formula; numeric MODEL confidence; initially 75 low threshold; tree agreement only | 4.9.2 equation; NFR-ACC-08 |
| Cold start | Average available validated category sales, configured base only when empty; four context factors; null confidence/model reference | 4.5.3-4.5.4, 4.9.2; FR-DP-06/07, NFR-ACC-08 |
| History/model governance | unitsSold target; exact origins and actual/imported/simulation selection; distinct days; untouched later holdout; same RF/LR data; separate candidates/evaluation/activation/restoration; higher-MAE rejection | 3.4.4, 3.5-3.6, 4.5, 4.9; NFR-ACC-01-07 |
| Joint feasibility | Reserve confirmed/unprocessed commitments, allocate remaining stock in display_order, replace revised quantities and recalculate; no automatic buffer | 4.9.3; FR-INV-07-12 |
| FEFO | Eligible batches by expiry_date then received_date then id; receipt-order/expiry-order divergence case | User revision 2026-10-16; replaces FIFO in 4.5.3-4.5.4 and 4.9.3 |
| Official POS | Stored prediction plus manager confirmation; current-date default; context once; atomic inventory/production/transactions/results/history; duplicate-safe | 4.5.4, 4.9.3; BR-INV-05/06, BR-POS-01/07, FR-POS-08 |
| Administration | Exact single profile role/status, no admin inheritance, final-admin guard, concrete Services/Repos/endpoints/Views and nonsecret settings/audit | 3.4.1, Table 4.27, 4.8; BR-UAM-03, FR-UAM/ADM |
| Notification design | recipient_user_id, per-type preferences, owned tokens, tracked delivery states, scoped foreground SELECT exception and Node writes | 4.2.4, 4.5, 4.8; FR-ALT-01-04 |
| Pending actions | Compute on opening/refresh/request; event-based alerts; no scheduled daily promises or operations | 1.4.1-1.4.2 |
| Schema | 29 public application tables + managed auth.users; one view, zero PostgreSQL enum types; 21 controlled CHECK domains; normalized allocations and unique operational links | 4.5.1-4.5.4, Tables 4.15-4.19 |
| Reporting | units_sold minus predicted error; leftover separate from discarded waste; FEFO batch-cost/transaction-price snapshots; signed profit; zero denominators unavailable; no duplicate totals | 4.5.3-4.5.4, 4.7.2 |
| Donation/export | Positive confirmed locked allocations, active charity/disposal reason; status endpoint; cancellation accounting open; manual date/period/category weekly CSV/PDF | 4.5.4, 4.7.1-4.7.3; FR-LDW/RPT |
| Measurable quality | Report environment, timing percentiles, viewport range, independent UAT completion; meaningful fault/concurrency/role/metric checks remain planned | 3.6, 4.10; NFR-PER/USA/COM |

Active implementation orders, verification lists, endpoint/artifact catalogues and code fences were rewritten, rather than leaving incompatible examples below a superseding banner. Historical designs remain available in Git history; historical dates are not relabelled as new testing evidence.

## Functional-module and boundary map

The module numbers below are the report's eight modules. Roles: **M** = ACTIVE BAKERY_MANAGER; **A** = ACTIVE SYSTEM_ADMINISTRATOR; **Both** = own/permitted data only after JWT and profile checks. No account has both stored roles. All routes are planned Express routes unless Supabase Auth is explicitly named.

| Key / functional module | Markdown sections | Services / Repos / endpoints | Permissions |
|---|---|---|---|
| B1 / 1 User and Access Management | [Node README Sections 2-3](Final%20Year%20Project/nodejs_middleware/README.md); [logical catalogue Section 2](logical_view_canonical_design.md) | SupabaseAuthClient login/logout; ProfileService/UserProfileRepo GET/PATCH `/api/profile`; UserAdministrationService/AuthAdminAdapter/UserProfileRepo GET/POST `/api/admin/users`, PATCH `/:id` | Both own profile/session; A users/roles/status |
| B2 / 2 Demand Prediction | [ML README Sections 3-7](Final%20Year%20Project/ml_prediction/README.md); [schema prediction/history](database_canonical_design.md) | PredictionOrchestrationService, PredictionService, FeaturePreparationService, ColdStartService, ConfidenceService; DailySalesRecordRepo/DailyPredictionRepo; POST `/api/predictions`, GET `/api/predictions/:date`; ContextService/WeatherRepo/CalendarRepo | M generates; permitted prediction/report reads |
| B3 / 3 Inventory and Smart Production Recommendation | [Inventory README](Final%20Year%20Project/inventory_integration/README.md); [schema inventory/decision](database_canonical_design.md) | InventoryService/RecipeService/RecommendationEngine/ProductionDecisionService/FefoBatchService; InventoryBatchRepo/InventoryLogRepo/RecipeRepo/ProductionDecisionRepo; `/api/admin/ingredients,batches,categories,recipes`; GET `/api/inventory`, `/api/recommendations/:date`; PUT `/api/production-decisions` | A master/batch writes; M planning/confirmation |
| B4 / 4 POS and Sales Simulation | [POS README](Final%20Year%20Project/pos_simulation/README.md); [architecture Section5](Final%20Year%20Project/ARCHITECTURE.md) | PosSimulationService/TransactionRecordingService/SimulationCommitRepo/DailyResultRepo/DailySalesRecordRepo; POST `/api/simulations`, GET `/api/simulations/:date`, GET `/:date/transactions` | M runs; permitted result/report reads |
| B5 / 5 Leftover, Donation and Waste Management | [Donation README](Final%20Year%20Project/donation_dashboard/README.md); [schema allocations](database_canonical_design.md) | LeftoverManagementService/DailyResultRepo/DonationRepo/WasteRecordRepo; GET `/api/leftovers`, GET `/api/leftovers/:resultId/recommendation`; POST `/api/donations`, `/api/waste-records`; PATCH `/api/donations/:id/status`; CharityPartnerService/CharityPartnerRepo `/api/admin/charity-partners` | M allocation/status; A charity records |
| B6 / 6 Reporting and Dashboard | [Donation README reporting/export](Final%20Year%20Project/donation_dashboard/README.md); [project plan Section 6](Final%20Year%20Project/fyp_food_waste.md) | DashboardService/ReportService/ReportRepo/ReportExportAdapter/IngredientCostService; GET `/api/dashboard`, `/api/reports`, `/api/reports/export` | Both, permitted data; manual read/export |
| B7 / 7 Alerts and Notifications | [Node README Sections 6-7](Final%20Year%20Project/nodejs_middleware/README.md); [Module 6 README](Final%20Year%20Project/operation_reminders_testing/README.md) | NotificationService/PendingActionService; NotificationRepo/NotificationPreferenceRepo/FcmTokenRepo/NotificationDeliveryRepo/FcmPushAdapter; GET `/api/notifications`, PATCH `/:id/read`; GET/PATCH `/api/notification-preferences`; POST/DELETE `/api/fcm-tokens`; GET `/api/pending-actions`; recipient Realtime | Both own notifications; events routed by permission |
| B8 / 8 System Administration | [Node README Sections 2-4](Final%20Year%20Project/nodejs_middleware/README.md); [ML README Section 6](Final%20Year%20Project/ml_prediction/README.md) | SettingsService/BakerySettingsRepo/SystemSettingsRepo GET/PATCH `/api/admin/settings`, GET `/api/admin/service-status`; AuditService/SystemLogRepo GET `/api/admin/audit`; ModelManagementService/MlModelVersionRepo/ModelEvaluationRepo/FastApiMlClient GET `/api/admin/models`, POST `/api/admin/models/train`, POST `/:id/evaluate`, `/:id/activate`, `/:id/restore` | A only; no manager operational inheritance |

Technical modules 0-6 map to these eight functional modules in [the project scope table](Final%20Year%20Project/fyp_food_waste.md#functional-modules-and-technical-build-mapping) and [structure chart](Final%20Year%20Project/structure_chart.md). Cross-cutting NFR rows below use the same boundary keys and permissions; they never grant new access.

## Requirements traceability matrix

Each ID is taken from the latest report tables (BR:3.4.4, FR:3.5, NFR:3.6). Boundary keys resolve to the Markdown sections, Services/Repos/endpoints and roles immediately above. Planned verification is elaborated in [Module 6](Final%20Year%20Project/operation_reminders_testing/README.md) and [database verification](database_schema_verification.md). All rows describe future checks, not passed tests.

The matrix covers **116 distinct requirements: 26 BR, 58 FR and 32 NFR IDs**.

### Business rules

| Report ID | Functional boundary / sections / permissions (map above) | Planned verification |
|---|---|---|
| BR-UAM-01 | B1 | Reject missing/expired JWT and missing/inactive profile. |
| BR-UAM-02 | B1/B8 | Reject each manager-only action for administrator and vice versa. |
| BR-UAM-03 | B1/B8 | Concurrent demotion/deactivation cannot remove final active administrator. |
| BR-DP-01 | B2 | Only manager request generates next-day prediction. |
| BR-DP-02 | B2 | Use latest valid origin-prioritized history and target-date context. |
| BR-DP-03 | B2 | 29/30 distinct-day and invalid-model boundaries select correct mode. |
| BR-DP-04 | B2 | Target remains unitsSold when lostSales differs. |
| BR-DP-05 | B2/B8 | Retraining creates candidate; active unchanged until explicit activation. |
| BR-INV-01 | B3 | Missing stored prediction/recipe/inventory blocks recommendation. |
| BR-INV-02 | B3 | Display-order allocations cannot reuse shared flour/butter/yeast. |
| BR-INV-03 | B3 | Replace revised decision; jointly feasible reasoned override only. |
| BR-INV-04 | B3 | Identify per-ingredient shortages and reduced/restock options. |
| BR-INV-05 | B3/B4 | Expiry order wins when receipt order differs; expired/inactive excluded. User revision replaces this report rule's FIFO ordering. |
| BR-INV-06 | B3/B4 | Duplicate/concurrent run deducts each confirmed decision once. |
| BR-POS-01 | B4 | Default current date; missing confirmation/prediction rejected. |
| BR-POS-02 | B4 | Sold cannot exceed confirmed produced quantity. |
| BR-POS-03 | B4 | Demand above remaining stock increments lost sales. |
| BR-POS-04 | B4 | Estimated demand equals sold plus lost sales. |
| BR-POS-05 | B4 | Leftover equals produced minus sold. |
| BR-POS-06 | B4 | One atomic commit includes all operational rows and validated history. |
| BR-POS-07 | B4 | Contextual multiplier already in prediction is not applied twice. |
| BR-LDW-01 | B5 | Concurrent donation/waste preserve donated+wasted+remaining=leftover. |
| BR-LDW-02 | B5 | Reject zero/negative donation and inactive charity. |
| BR-LDW-03 | B5 | Reject zero/negative waste and missing disposal reason. |
| BR-RPT-01 | B6 | Report reads do not mutate source rows or add detail to daily totals. |
| BR-ALT-01 | B7 | Event push requires recipient opt-in and owned active token. |

### Functional requirements

| Report ID | Functional boundary / sections / permissions (map above) | Planned verification |
|---|---|---|
| FR-UAM-01 | B1 | Valid authentication plus ACTIVE profile; invalid credentials denied. |
| FR-UAM-02 | B1 | Logout removes session and recipient subscription/token registration. |
| FR-UAM-03 | B1 | Own editable profile only; role/status injection denied. |
| FR-UAM-04 | B1/B8 | Stored role checked for each endpoint; forged email/body roles ignored. |
| FR-UAM-05 | B1/B8 | Admin account/role changes are validated/audited; final admin retained. |
| FR-DP-01 | B2 | Validate exact origins/source links; deduplicate actual > imported > simulation. |
| FR-DP-02 | B2 | Lag/rolling/trend/same-weekday features use past observations only. |
| FR-DP-03 | B2 | Target-date weekday/weekend/month/monsoon derived consistently. |
| FR-DP-04 | B2 | Weather/holiday dates match; retry or labelled configured fallback. |
| FR-DP-05 | B2 | Manager manual next-day request iterates configured active categories. |
| FR-DP-06 | B2 | MODEL requires >=30 selected distinct days and active valid RF. |
| FR-DP-07 | B2 | Cold start uses observed mean; configured base only for no observations. |
| FR-DP-08 | B2 | Round/clamp prediction; persist/display mode/factors/version; null heuristic confidence. |
| FR-DP-09 | B2/B8 | Only administrator requests candidate training on validated unitsSold. |
| FR-DP-10 | B2/B8 | RF/LR receive identical training/test observations. |
| FR-DP-11 | B2/B8 | MAE/RMSE/MAPE/R-squared, zero handling and unavailable metrics correct. |
| FR-DP-12 | B2/B8 | Separate evaluate/activate/restore; retained history and failure keeps active. |
| FR-INV-01 | B3/B8 | Only administrator edits ingredient/category/recipe records. |
| FR-INV-02 | B3/B8 | Validate batch quantities/dates and immutable normalized unit-cost snapshot. |
| FR-INV-03 | B3/B8 | Restock and movement rows reconcile batch/snapshot balances. |
| FR-INV-04 | B3/B7 | Low-stock/expired/expiring detection creates permitted recipient events. |
| FR-INV-05 | B3 | Production-date eligibility excludes expired/inactive/future-received batches. |
| FR-INV-06 | B3/B4 | FEFO expiry-date/receipt-date/id ordering; explicit user change from report FIFO. |
| FR-INV-07 | B3 | Whole max quantity uses remaining ingredient balance minimum. |
| FR-INV-08 | B3 | Reserve commitments and prior display-order recommendations first. |
| FR-INV-09 | B3 | Shortage response suggests feasible reduction/restocking. |
| FR-INV-10 | B3 | Manager accepts/reduces/overrides stored recommendation explicitly. |
| FR-INV-11 | B3 | Reason for changed recommendation; joint stock validation under locks. |
| FR-INV-12 | B3 | Decision links prediction/date/category and server-derived actor; no deduction. |
| FR-POS-01 | B4 | Manager initiation only; indicators cannot initiate simulation. |
| FR-POS-02 | B4 | Bakery-local current-date default and explicit stored confirmed decision. |
| FR-POS-03 | B4 | Retain date-matched weather/holiday context without reapplying multipliers. |
| FR-POS-04 | B4 | Time-slot/stochastic sales bounded by produced quantity. |
| FR-POS-05 | B4 | Lost sales preserved separately from sold/training target. |
| FR-POS-06 | B4/B6 | Estimated demand, transaction-price revenue and leftovers balance. |
| FR-POS-07 | B4/B2 | One validated SIMULATION_GENERATED record/category links committed result. |
| FR-POS-08 | B3/B4 | Deduct before sales exactly once; injected failure rolls back all tables. |
| FR-LDW-01 | B5 | Read leftover from completed DailyResult. |
| FR-LDW-02 | B5 | Recommend action only; no automatic allocation. |
| FR-LDW-03 | B5 | Confirmed positive donation uses active charity. |
| FR-LDW-04 | B5 | Confirmed positive waste stores disposal reason. |
| FR-LDW-05 | B5 | Locked allocation cannot exceed remaining quantity under concurrency. |
| FR-LDW-06 | B5 | Status endpoint audits pending/collected/completed; cancellation policy explicit. |
| FR-LDW-07 | B5/B8 | Administrator manages charity activation; manager cannot mutate partners. |
| FR-RPT-01 | B6 | Dashboard fields match stored production/sales/lost sales/leftover/allocation. |
| FR-RPT-02 | B6 | Date/period/category filters affect UI/export identically. |
| FR-RPT-03 | B6 | Manually generated weekly/seven-day report aggregates stored records. |
| FR-RPT-04 | B2/B6 | Comparable selected unitsSold minus prediction, preserving signed error. |
| FR-RPT-05 | B6 | Leftover/discarded-waste/fulfilment rates differ; zero denominators unavailable. |
| FR-RPT-06 | B6 | CSV/PDF share values and origin labels; date/numeric/file output validated. |
| FR-ADM-01 | B8 | Singleton bakery and typed operational settings validate ranges. |
| FR-ADM-02 | B8 | Thresholds/factors configurable; no numeric cold-start confidence. |
| FR-ADM-03 | B8 | Nonsecret connection configuration; secrets outside DB/client/repository. |
| FR-ADM-04 | B8 | Important actions append actor/entity/outcome/timestamp; audit is read-only. |
| FR-ALT-01 | B7 | Low stock/expiry/confidence/lost sales/surplus/status/failure event coverage. |
| FR-ALT-02 | B7 | Two recipients cannot see each other through Node or Realtime. |
| FR-ALT-03 | B7 | Node ownership check on mark-read; no global read/dedupe state. |
| FR-ALT-04 | B7 | Opt-in/token gates; PENDING/SUBMITTED/DELIVERED/FAILED/SKIPPED evidence. |

### Non-functional requirements

| Report ID | Functional boundary / sections / permissions (map above) | Planned verification |
|---|---|---|
| NFR-PER-01 | B1/B2/B3/B6/B7 | Reference environment: >=95% of specified <=50-row screen requests within 3 s. |
| NFR-PER-02 | B2/B3 | <=15s prediction/recommendation at 20 categories and 365 daily records/category. |
| NFR-PER-03 | B4/B6 | <=30s 12-hour simulation or seven-day report for 20 categories. |
| NFR-SEC-01 | B1-B8 | Reject unauthenticated/expired sessions before protected operations. |
| NFR-SEC-02 | B1-B8 | Cross-role and forged-role tests at every mutation boundary. |
| NFR-SEC-03 | B1 | Provider-managed passwords; no plaintext storage/transmission/logging. |
| NFR-SEC-04 | B1-B8 | Review HTTPS/TLS 1.2+ for all protected component links. |
| NFR-SEC-05 | B1-B8 | Inspect proposed config/client/exports/logs for secret exclusion. |
| NFR-REL-01 | B3/B4/B5/B8 | Inject transaction failures; no partial deductions/results/history/allocations. |
| NFR-REL-02 | B2/B8 | Training/evaluation/activation failure preserves active model. |
| NFR-REL-03 | B2/B7/B8 | External failure yields clear retry or labelled controlled fallback. |
| NFR-REL-04 | B3/B4/B5 | Nonnegative physical quantities; signed errors/profits still permitted. |
| NFR-USA-01 | B1-B8 | Review consistent role navigation, terminology, color and controls. |
| NFR-USA-02 | B1-B8 | Field validation/confirmation/retry and null/Not Applicable messages clear. |
| NFR-USA-03 | B1-B8 | 360x640 through 412x915 dp: no clipping/overlap/required horizontal scrolling. |
| NFR-USA-04 | B1/B2/B3/B4/B5 | >=80% independent completion: login, prediction, confirmation, simulation, leftovers. |
| NFR-MAI-01 | B1-B8 | Review View/client/Controller/Service/Repo and thin FastAPI boundaries. |
| NFR-MAI-02 | B8 | Configurable thresholds/factors; fixed requirement invariants retained. |
| NFR-MAI-03 | B1-B8 | Consistent class/DTO/storage names; route modules not UML classes. |
| NFR-COM-01 | B1-B8 | Android 10+ devices,  >=4 GB RAM reference environment. |
| NFR-COM-02 | B1-B8 | Cross-language JSON/mode/null/enum/date/quantity contract equivalence. |
| NFR-DAT-01 | B1-B8 | Validate fields/quantities/dates/FKs and server ownership before writes. |
| NFR-DAT-02 | B1-B8 | Catalogue IDs, timestamps, uniques and operational relationship checks. |
| NFR-DAT-03 | B3/B8 | Audit user/config/inventory/model/production actions with server actor. |
| NFR-ACC-01 | B2/B8 | Chronologically later holdout never used for fit/parameter selection. |
| NFR-ACC-02 | B2/B8 | Zero actuals remain MAE/RMSE; excluded only from MAPE; all-zero MAPE unavailable. |
| NFR-ACC-03 | B2/B8 | Four metrics and undefined/constant-target R-squared handled honestly. |
| NFR-ACC-04 | B2/B8 | Dataset identity for RF/LR train/test comparisons matches. |
| NFR-ACC-05 | B2/B8 | Higher candidate MAE on same later holdout rejects activation atomically. |
| NFR-ACC-06 | B2/B6 | Persist prediction and corresponding unitsSold; signed sold-minus-predicted error. |
| NFR-ACC-07 | B2/B6 | Simulation-containing evaluation/export labelled simulation-based. |
| NFR-ACC-08 | B2/B7 | Confidence boundaries mu=0/sigma=0/large sigma and 75 threshold; cold start null. |

## Validation performed for this reconciliation

Document validation is separate from application testing. Source requirements and embedded equations were reviewed; schema catalogue counts, DTO nullability, controlled values, endpoint/class names, diagrams, examples, implementation order and planned verification were cross-checked. The final static review on 2026-10-12 checked all 22 planning documents: 151 local Markdown links and their referenced headings resolve, 48 code fences are balanced, and the JSON example parses. All 116 report requirement IDs occur in the traceability matrix, with no missing or invented IDs; these IDs also match the extracted DOCX. The catalogue contains 29 public tables plus managed auth.users and one computed view, with 21 controlled domains and no PostgreSQL ENUM types. Every ERD entity's fields match its catalogue field dictionary.

During the 2026-10-12 review, targeted searches found no active obsolete confidence, optional-confirmation, expiry-first FIFO, scheduled-workflow, immediate-activation or automatic-donation guidance. `git diff --check` passes. The final Git path review is confined to the 22 planning Markdown files plus the user's pre-existing deletion of FYP Report.md. The untracked report mirror remains byte-identical to the supplied Downloads copy. Mermaid relationships were inspected as design text; no diagram renderer or application test suite was installed or run.

No application tests, ML training, migrations, dependency installation or deployment were run. The timing, UAT, transaction, authorization and other checks in the matrix are test plans to execute after implementation. A successful documentation check is not evidence that those behaviors already work.

## Genuinely unresolved decisions and future scope

- **Donation cancellation:** the report names cancellation but does not settle allowed cancellation transitions, whether/how reserved donated quantities return to remaining leftovers, or permitted reallocation after collection. Keep an explicit open decision; do not implement an implicit release or claim a tested cancellation flow.
- **Future scope:** replacing a completed simulation requires a separate atomic policy for exact original batch movements, dependent allocation/history and audit. Scheduled reminders/background scheduling are also future work. Neither is promised in the present implementation order.

First model activation requires valid candidate evaluation, administrator review and explicit confirmation; no incumbent comparison is fabricated when no active model exists. Quantity rounding uses nearest integer with half ties away from zero as a shared engineering convention; confidence is persisted without display-scale rounding. The revised documents also make routine design elaborations explicit, including uppercase status mappings, batch cost units, endpoint names and metadata for reproducing identical holdout datasets. These are planning choices for implementing the report, not additions to completed functionality or reasons to stop this documentation work.

## FEFO revision - 2026-10-16

The user explicitly changed rotation from FIFO to FEFO. This revision updates 20 planning Markdown files: the overview/architecture/structure chart; MODULE and README for data foundation, Node middleware, inventory integration, POS simulation, donation/dashboard and operation/testing; and the five root design/verification/change documents. The two ML documents contain no affected rotation contracts and are unchanged.

Revised active algorithms, SQL query/index examples, FefoBatchService references, diagrams, implementation orders, cost descriptions and verification expectations use expiry_date, received_date, id ascending. Eligibility, shared commitments, atomicity and immutable consumed-batch costs are unchanged. Fixtures now require the newer but earlier-expiring batch to be consumed first, with receipt-date and ID tie-break cases. BR-INV-05 and FR-INV-06 retain their report IDs but explicitly record the changed acceptance expectation. The report DOCX and its Markdown mirror still describe FIFO and require a separate report revision to align with this user decision.

Validation: inspected the diff and searched affected planning documents for obsolete receipt-first guidance and service/index names; git diff --check passed. Only these planning Markdown files changed in this revision. Existing untracked supabase files were left untouched; the inventory-batches migration is empty locally. No SQL was executed and no application tests were run. Prior dated audit results above remain historical evidence, not new test results.
