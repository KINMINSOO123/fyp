# Module 6: Manual Workflow and Verification — Detailed Plan

**Reconciled:** 2026-10-11 against the latest `RSW_SooKinMin_Project1 (1).docx`, especially Sections 1.4, 3.4.4–3.6, 4.5.3–4.5.4, 4.7–4.10 and Table 4.27. **Status:** planned acceptance criteria and test procedures, not executed tests or completed results. The repository contains a Flutter starter and design Markdown. The [report mirror](../../RSW_SooKinMin_Project1.docx.md) supports navigation; the DOCX is the authority.

## 1. Scope, dependencies and evidence

Technical Module 6 integrates request-derived pending indicators and tests all eight functional modules. It depends on Module 0 schema/contracts; Module 1 authentication, administration, notification and external-adapter boundaries; Module 2 prediction/model lifecycle; Module 3 joint ingredient planning/FIFO; Module 4 atomic simulation; and Module 5 allocation/reporting. It does not add a ninth functional module or replace the report's eight-module mapping.

Each future test record should contain the BR/FR/NFR IDs, dataset/fixture, authenticated role, action, expected result, actual result, environment and evidence reference. Preserve failures and unavailable measurements; do not manufacture achieved accuracy, timing or UAT results. Vitest/pytest/Flutter testing may be used when implementation exists, but this task does not install packages, create executable tests, migrate a database or deploy services.

## 2. Pending-action contract and event delivery

`GET /api/pending-actions?date=YYYY-MM-DD` follows `PendingActionController -> PendingActionService -> DailyPredictionRepo/ProductionDecisionRepo/DailyResultRepo`, with donation/waste reads where needed. A successful response describes applicable pending work, prerequisite status, selected date and role-permitted actions. Manager items include missing next-day predictions, unconfirmed production, confirmed unsimulated production and remaining unallocated leftovers. Administrator items concern permitted configuration/model/administration work. These are derived DTOs, not scheduled reminder rows or new tables.

Invoke the read when the user opens/refreshes the application or explicitly requests the state. It does not call prediction generation, model training, recommendation mutation, confirmation, simulation or allocation. A pending indicator becomes an explicit action only after the authorized user selects and confirms it.

There is no current-scope timed scheduler, daily 06:00/18:00 reminder promise, automatic donation or automatic model retraining. Timed reminders remain future work. Foreground Supabase Realtime and background FCM deliver eligible events; neither executes the pending business action.

Events cover low stock, expiring/expired batches, low confidence, lost sales, excessive surplus, donation-status changes and external/system failures. `NotificationService` selects intended authorized recipients, stores per-recipient notifications, checks per-type preferences and recipient-owned valid active tokens, and tracks per-device delivery attempts. All notification writes/read-state changes use Node. Recipient-scoped authenticated SELECT for notification Realtime is the explicit limited exception to normal application-table access restrictions.

## 3. Manual end-to-end scenario

1. The System Administrator configures active categories, positive recipes, valid inventory batches, an active charity and nonsecret settings. Include more than the four example categories in workload fixtures. Authentication uses Supabase Auth; stored profile status/role controls protected Node access.
2. Prepare validated units-sold history with exact origins, including a cold-start category and a category with at least 30 distinct valid days and a valid active model. In a separate administrator sequence, candidate training, evaluation and activation/restoration require individual authorized actions.
3. A Bakery Manager opens/refreshes the dashboard; `GET /api/pending-actions` displays prerequisites without writing business data. The administrator's View does not expose or gain manager-only actions.
4. The manager calls `POST /api/predictions` for the next day. Inspect mode-specific confidence and context traceability, then `GET /api/recommendations/:date` for the joint ingredient plan.
5. The manager confirms or feasibly overrides using `PUT /api/production-decisions`; an override has a reason. Check shared requirements and unchanged stored inventory after confirmation.
6. On the applicable simulation date, `POST /api/simulations` defaults to the bakery's current date. The stored prediction and confirmed decision are mandatory. One Node-owned transaction/RPC locks/revalidates stock, consumes valid batches in `received_date, id` order and commits inventory, movements, production, transactions, DailyResult and validated simulation-origin history together.
7. Fetch `GET /api/simulations/:date` and transactions. Check units sold, lost sales, analytical estimated demand, leftovers and price/cost snapshots; show Simulated Data. Retry the same official request and prove that no ingredient is deducted twice.
8. Read leftovers; manager confirms positive donation/waste quantities through `POST /api/donations` or `POST /api/waste-records`, then explicitly advances donation status through its permitted progress states. No donation or waste exists merely because surplus was produced.
9. Request `GET /api/reports` and `/api/reports/export` with a seven-day range/category filter and CSV/PDF format. Verify common calculations, origins, signed/undefined values and no duplicate aggregation.
10. Inspect recipient notifications through Node and foreground Realtime; background push occurs only for eligible preferences/tokens with independently tracked delivery status. Deactivate an account and prove subsequent protected operations are rejected.

This scenario is a future test script, not a demonstration that those functions already exist.

## 4. Access, administration and configuration checks

| Test | Fixture/action and expected outcome | Traceability |
|---|---|---|
| AUTH-01 | Missing/invalid/expired JWT, wrong issuer/audience/signature, or valid JWT with missing/inactive profile: reject before domain operation; no writes | BR-UAM-01; FR-UAM-01/04; NFR-SEC-01/02 |
| AUTH-02 | Administrator attempts prediction, production confirmation, simulation or allocation/status; manager attempts catalogue, charity, model, users/roles/settings/audit administration: reject each forbidden action | BR-UAM-02; Table 4.27; NFR-SEC-02 |
| AUTH-03 | Forge email role, body actor/role/confirmedBy/feasibility or another user's recipient/token identity: no privilege or ownership is gained | FR-UAM-04; NFR-DAT-01; §4.8 |
| AUTH-04 | Own-profile edit changes permitted fields only; role/status fields rejected; both roles can read permitted dashboard/reports and own notifications | FR-UAM-03/04; Table 4.27 |
| AUTH-05 | Demote/deactivate final active administrator, including two concurrent administrator removals: at least one remains ACTIVE/SYSTEM_ADMINISTRATOR | BR-UAM-03; UC-ADM-01 |
| ADM-01 | Invalid role/status, negative/out-of-range threshold, invalid singleton settings or secret-valued configuration rejected; existing settings remain on failure | FR-UAM-05; FR-ADM-01/02/03; NFR-REL-01; NFR-MAI-02 |
| ADM-02 | Authorized settings/user/model/inventory/decision changes record actor/action/entity/outcome/time; audit list filters correctly; no edit/delete through View/API | FR-ADM-04; NFR-DAT-02/03 |
| SEC-01 | Passwords handled by Supabase Auth; no plaintext passwords, tokens/API keys in profile/settings/logs/export/client; TLS 1.2+; FastAPI accepts protected Node traffic and has no database credentials | NFR-SEC-03/04/05; §§4.2.4, 4.8 |

Account/provider failure tests must distinguish local transaction rollback from external Authentication side effects. A partially provisioned account must not acquire ACTIVE application access without a valid stored profile. Role changes affect subsequent requests; a cached client role does not override the server profile.

## 5. Historical data, cold start, confidence and evaluation

| Test | Fixture/action and expected outcome | Traceability |
|---|---|---|
| DATA-01 | Same category/day has all three origins; select one validated ACTUAL_TRANSACTION before IMPORTED_HISTORICAL before SIMULATION_GENERATED. Invalid higher-priority records do not block a valid lower-priority row; deduplicate before counting days | FR-DP-01/02; §§4.5.3, 4.9.2 |
| DATA-02 | Simulation-origin row links its DailyResult; actual/imported row retains external source reference. Repeated source import does not produce extra eligible observations | FR-DP-01; NFR-DAT-01 |
| DATA-03 | Change lost sales while keeping units sold fixed: model target and comparable prediction error remain units sold; analytical estimated demand changes only | BR-DP-04; FR-RPT-04; NFR-ACC-06 |
| PRED-01 | 29 distinct selected valid days -> COLD_START; 30 plus valid active model -> MODEL. Thirty rows containing duplicate dates are insufficient. Thirty days without a valid active model -> COLD_START | BR-DP-03; FR-DP-06/07; §4.9.2 |
| PRED-02 | Valid units sold 10 and 20 with configured base 100, all factors 1 -> cold-start quantity 15. No valid observations -> configured base. Validate each weekday/monsoon/weather/holiday factor applied once and result nonnegative whole quantity | FR-DP-07; §4.9.2 |
| PRED-03 | Every COLD_START DTO/SQL/UI requires null confidence and null model version; label low-confidence heuristic. Every MODEL response requires finite numeric confidence [0,100] and applicable valid model reference | NFR-ACC-08; §§4.5.3–4.5.4 |
| CONF-01 | `mu=100, sigma=0 -> 100`; `mu=100, sigma=25 -> 75`; `mu=100, sigma=30 -> 70`; `mu=0, sigma=0 -> 100`; `mu=0, sigma=2 -> 0`. Check denominator floor and clamping with boundary inputs | NFR-ACC-08; §4.9.2 |
| CONF-02 | At threshold 75, confidence 75 is not Low Confidence; 74.9 is. A changed configured threshold changes label/event eligibility. Model agreement is never labeled probability of accuracy | NFR-ACC-08 |
| EVAL-01 | Every test date is chronologically later than fitting/parameter-selection dates; test rows untouched during training/tuning; RF/LR receive identical training/test rows | NFR-ACC-01/04; FR-DP-10 |
| EVAL-02 | MAE/RMSE include zero-sales observations; MAPE excludes only zero actuals; all-zero MAPE unavailable; undefined R² unavailable rather than coerced to 1 or 0. Store all four metric names and provenance | NFR-ACC-02/03/07; FR-DP-11 |
| MODEL-01 | Administrator training creates inactive CANDIDATE only; evaluation/activation/restoration are separate confirmed actions; manager cannot invoke them | BR-DP-05; FR-DP-09/12 |
| MODEL-02 | Active and candidate evaluated on the same later dataset: candidate MAE 6 versus active 5 -> reject activation, active unchanged. Equal MAE is not rejected by the higher-MAE rule alone | NFR-ACC-05 |
| MODEL-03 | Training/evaluation/storage/activation/restoration failure preserves previous active model and rollback leaves no partial active state. Missing valid comparison cannot be treated as success | NFR-REL-02 |

`ConfidenceService` is the calculation boundary; tests should call that boundary and assert report-defined behavior. Prediction quantity uses `max(0, round(mu))`; cold start uses `max(0, round(Bc * Dt * Mt * Wt * Ht))`. Formula tests include both zero mean and high variance. The image-embedded report equations are the specification, not a historical numerical example.

Origin labels remain visible in performance reports. Simulation-based results do not establish real-world accuracy. MAPE < 10% and R² > 0.85, if tracked, are optional aspirations rather than report-mandated gates or achieved results. First activation with no active model requires valid candidate evaluation, administrator review and explicit confirmation. Its missing active-model comparator is not replaced with fabricated metric targets. Verify the initial activation separately from replacement of an active version.

## 6. Shared inventory, FIFO and production decision checks

| Test | Fixture/action and expected outcome | Traceability |
|---|---|---|
| INV-01 | Two categories share 1,000 g flour and each uses 10 g/unit; each predicts 80. With no commitments and A before B, recommend A=80 then B=20, not 80 each | BR-INV-01/02; FR-INV-07/08; §4.9.3 |
| INV-02 | Confirmed unprocessed A=60 first reserves 600 g; B max 40. Revising A to 30 replaces 60 and leaves 700 g, without double-counting either version | BR-INV-03; §4.9.3 |
| INV-03 | Commitments alone require 1,100 g from 1,000 g: report shortage and require correction; do not generate a falsely feasible rest-of-plan | BR-INV-04; FR-INV-09 |
| INV-04 | Processed decisions do not reserve stock again. Confirmation writes no inventory movements. Each newly recommended quantity decreases the temporary shared balance in ascending display_order | BR-INV-06; §§4.5.4, 4.9.3 |
| INV-05 | Each category has multiple recipe ingredients; maximum is minimum whole-number quantity supported across remaining balances. Missing recipe/inactive ingredient or zero recipe requirement is rejected/reported | FR-INV-01/07/08; NFR-DAT-01 |
| INV-06 | Feasible manager override above recommendation requires reason and combined-stock validation; no automatic production buffer above predicted sales | BR-INV-03; §4.9.3 |
| FIFO-01 | Production date 2026-10-11: batch A received Oct 1 expires Oct 30; B received Oct 2 expires Oct 20. Both valid: consume A first despite B's earlier expiry | BR-INV-05; §§4.5.3, 4.9.3 |
| FIFO-02 | Same received_date: consume lower id first. Inactive/expired batches excluded. Query/index/design ordering is received_date then id, not expiry-first FEFO | FR-INV-05/06; §4.5.3 |

Test concurrent confirmations against the same shared inventory and verify combined outstanding commitments never become an accepted infeasible plan. Re-check at official simulation time because stock or expiry may change after confirmation. Recipes/units must use consistent conversions in planning, deductions and cost calculations.

## 7. Atomic simulation and failure tests

The tested boundary is `PosSimulationService -> SimulationCommitRepo` and one Node-owned PostgreSQL transaction/RPC. The official request contains only permitted date input, defaulting to current bakery date, not a produced override. Stored prediction and explicit manager confirmation must exist for every selected category/date. Generated random transactions remain inside the proposed atomic workflow; test-only calculation fixtures do not persist operational records.

| Test | Action and expected outcome | Traceability |
|---|---|---|
| POS-01 | Missing prediction, wrong-date decision, unconfirmed decision or caller-supplied producedOverride: reject; no fallback to recommendation | BR-POS-01; §§4.5.4, 4.9.3 |
| POS-02 | Fixed stored contextualised prediction and controlled random variation; weather/holiday/season changes do not multiply the already contextualised baseline again | BR-POS-07; §4.9.3 |
| POS-03 | Sold <= confirmed production; lost sales = max(0,demand-produced); estimated demand = sold+lost; leftover = produced-sold; all quantity invariants nonnegative | BR-POS-02–06; NFR-REL-04 |
| POS-04 | Two identical concurrent official requests: locks and unique links permit one completion; repeat completed requests return `409 ALREADY_SIMULATED` with a stored-result link and no writes, never another deduction/result/history row | BR-INV-06; NFR-DAT-01 |
| POS-05 | After confirmation, stock reduced/expired or another outstanding commitment exists: joint revalidation under lock prevents infeasible deduction | BR-INV-02/05; §4.9.3 |
| POS-06 | Inject a failure after batch update, inventory snapshot, movement, production, transaction, DailyResult, or DailySalesRecord write: all changes from the attempt roll back | NFR-REL-01; §4.5.4 |
| POS-07 | After rollback, before-state batch quantities/cost movements/history/unique links exactly match, and an explicit retry can safely complete once | NFR-REL-01; BR-INV-06 |
| POS-08 | Committed category/day produces one validated SIMULATION_GENERATED DailySalesRecord referencing its DailyResult; transaction unit price and actual consumed-batch cost remain historical snapshots | FR-POS-07/08; §§4.5.3–4.5.4, 4.7.2 |

Use failure injection at every persistence stage, not only a controller exception before work begins. Assert no partial stock deductions, financial snapshots or dangling history remains. Correction batches are not a substitute for rollback. Re-simulation is future work until exact original batch movements and all linked history can be reversed/replaced atomically; no current destructive re-run test should assume that policy exists. No SimulationRun or LeftoverRecord table is required for duplicate protection.

## 8. Allocation, reporting and export checks

| Test | Fixture/action and expected outcome | Traceability |
|---|---|---|
| LDW-01 | Zero/negative/excess quantity, inactive/missing charity, missing disposal reason or no completed simulation: reject, balances unchanged | BR-LDW-01/02/03; FR-LDW-01/03/04/05 |
| LDW-02 | Leftover 10, concurrent donation 7 and waste 6: serialize on DailyResult lock; at most one succeeds; donated+wasted+remaining equals 10 | FR-LDW-05; NFR-REL-01 |
| LDW-03 | Allocation insert or balance/audit update fails: whole allocation transaction rolls back. No automatic allocation on recommendation/dashboard read | FR-LDW-02/05; §4.9.3 |
| LDW-04 | PENDING -> COLLECTED -> COMPLETED requires manager confirmation and audit; quantity not deducted again. Cancellation mutation remains disabled pending accounting policy | FR-LDW-06; §4.6 |
| RPT-01 | Prediction 100, sold 80, produced 120 -> signed error -20 and leftover 40. Donated 25/wasted 5/unallocated 10 -> leftover rate 33.33%, discarded waste rate 4.17% | NFR-ACC-06; FR-RPT-04/05; §§4.5.3, 4.7.2 |
| RPT-02 | Consume 2 kg at RM3/kg and 1 kg at RM5/kg -> RM11 cost. RM8 revenue -> -RM3 gross profit and -37.5% margin. Later master-price change does not alter historical cost | §4.7.2 |
| RPT-03 | Zero produced/demand/revenue gives Not Applicable for corresponding percentages. No nonnegative check rejects legitimate negative profit/margin or signed error | §4.7.2; NFR-DAT-01 |
| RPT-04 | Aggregate transaction details or daily totals once; joins with multiple donations/transactions do not multiply revenue. Period ratios use summed numerator/denominator | BR-RPT-01; §4.7.2 |
| RPT-05 | UI/CSV/PDF with identical weekly/date/category filters return matching totals, costs, provenance and null semantics. Exports are manually requested and do not mutate history | FR-RPT-02/03/06; §4.7.3 |
| RPT-06 | CSV includes exact data_origin and raw numeric values; PDF visibly labels Simulated Data, period/category/time; neither includes secrets or claims real trading results | NFR-ACC-07; NFR-SEC-05 |

## 9. Notification and manual-state checks

| Test | Action and expected outcome | Traceability |
|---|---|---|
| NTF-01 | Users A/B have different notifications; Node list/mark-read and authenticated Realtime for A cannot expose/change B's rows; inactive profile loses access | FR-ALT-02/03; §§4.2.4, 4.8 |
| NTF-02 | Same event targets A/B; recipient-scoped dedup stores each authorized recipient's notification independently. A reading it does not mark B's read | FR-ALT-01/03; §4.5.3 |
| NTF-03 | Per-type push off -> SKIPPED and no provider send; invalid/inactive/wrong-user token never receives recipient's push. An eligible active token uses its authenticated owner | BR-ALT-01; FR-ALT-04 |
| NTF-04 | Track PENDING -> SUBMITTED on provider acceptance; DELIVERED only with evidence; failure -> FAILED; disabled/no eligible token -> SKIPPED with reason; timestamps/provider IDs match state | FR-ALT-04; §4.5.3 |
| NTF-05 | FCM unavailable/rejects token: in-app record retained, failure recorded, token deactivated where invalid, understandable retry; no data broadcast or false delivery claim | NFR-REL-03; FR-ALT-04 |
| NTF-06 | All required event types exercised: low stock, expiry, low confidence including heuristic labels, lost sales, surplus, donation status, model/external/system failure | FR-ALT-01; §§4.6, 4.8 |
| MAN-01 | Open/refresh pending state; inspect call graph/database changes: no prediction, training, confirmation, simulation or allocation executes | §§1.4.1–1.4.2 |
| MAN-02 | Advance test clock across formerly proposed reminder times with no user/event action: no scheduled reminder or business operation occurs | Scope §1.4 |

Foreground recipient SELECT is limited to the notification data needed by Supabase Realtime. Verify direct authenticated INSERT/UPDATE/DELETE is denied, other application-table reads remain unavailable, and token/preference/delivery/audit data are not published to general client subscriptions. Mark-read uses Node. Logout removes subscriptions and deactivates the relevant token registration.

## 10. Measurable performance, usability and compatibility

Use the report's reference environment: Android 10 or later, at least 4 GB RAM, stable network >=10 Mbps, available backend; up to 20 active bread categories, 365 daily records per category and 50 records per displayed list page. Record concrete device/OS, backend, data volume, network and cache conditions with actual results. Four seed categories are insufficient evidence for the upper reference workload.

| Requirement | Measurement plan and acceptance criterion |
|---|---|
| NFR-PER-01 | Measure user-request-to-render completion for login, dashboard, prediction-history, inventory-list, report-list and notification-list requests with at most 50 rows. At least 95% complete within 3 seconds; report counts/distribution per screen and overall so a slow screen is not hidden |
| NFR-PER-02 | At up to 20 categories and 365 records/category, next-day prediction and production recommendation each complete within 15 seconds |
| NFR-PER-03 | A full 12-hour simulated business day and a seven-day report for up to 20 categories each complete within 30 seconds |
| NFR-USA-01/02 | Consistent terminology/navigation/controls; clear validation, confirmation, loading, errors and retry states, including cold-start and Not Applicable labels |
| NFR-USA-03 | Verify 360×640 through 412×915 dp layouts: primary controls visible/reachable, no overlap/clipping or required horizontal scrolling; tables/charts adapt within the View |
| NFR-USA-04 | At least 80% of actual UAT participants complete login, prediction, production confirmation, simulation and leftover recording independently without moderator help or a task-blocking usability problem |
| NFR-COM-01/02 | Android 10+ compatibility and consistent Node/FastAPI/Flutter data formats, including null confidence, uppercase values, dates, quantity units and signed money |
| NFR-MAI-01/02/03 | Architecture review confirms Controller/Service/Repo/adapters, configured thresholds, consistent naming and no database access in Python or direct ordinary Flutter CRUD |

For UAT, define the five tasks and success rubric before execution, then record actual participant count, independent completion per task, blocked tasks and observations. The denominator is the participants actually assessed, not a fabricated planned cohort. Do not mark a task successful after moderator intervention. The plan specifies no invented participant number or completed percentage.

External-service failures are assessed separately under NFR-REL-03 with visible retry/configured fallback. Do not exclude unexplained slow requests or silently substitute ideal network conditions to claim a performance pass. Screen timing includes required data retrieval/rendering, while model training has no invented time target in the report.

## 11. Verification order and implementation status

1. Review schema/DTO/role/endpoint mappings and [requirement traceability](../../planning_documents_change_report.md) before creating fixtures.
2. Verify pure history selection, confidence, cold-start, report and quantity calculations at their Service boundaries.
3. Verify authentication/authorization, settings, provider failure handling and candidate model lifecycle.
4. Use transactional integration/concurrency tests for shared commitments, FIFO, duplicate simulation, all-or-nothing failure and allocations.
5. Verify recipient Realtime/FCM behavior, UI/export parity and request-derived pending state.
6. Execute the manual end-to-end scenario, then reference-environment performance, Android layouts and independent UAT.
7. Record actual outcomes/evidence and unresolved defects; preserve truthful historical audit dates and distinguish plans from results.

Donation cancellation/reallocation remains an explicit open decision in the [change report](../../planning_documents_change_report.md). First activation requires valid candidate evaluation, administrator review and explicit confirmation. Re-simulation with exact atomic reversal and timed reminders remain future work. This documentation reconciliation runs no implementation tests and invents no Chapters 5/6 implementation or evaluation results.
