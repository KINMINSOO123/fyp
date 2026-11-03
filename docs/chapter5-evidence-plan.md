# Chapter 5 Implementation and Testing Evidence Plan

**Project:** Smart Bakery Food Waste Reduction System  
**Plan date:** 31 October 2026  
**Purpose:** Future implementation, testing and evidence checklist. This is not a completed Chapter 5 and does not claim that unexecuted tests have passed.

## 1. Authority and evidence rules

Use the latest Project 2 report as the authoritative source for business rules, functional requirements and non-functional requirements. The current codebase and refined Markdown plans guide implementation details, but they do not replace the report requirements.

The official ingredient-consumption method is **First-Expired, First-Out (FEFO)**:

1. Select valid batches by earliest expiry date.
2. Use received date as the first tie-breaker.
3. Use batch ID as the second tie-breaker.
4. Exclude expired, inactive, depleted, future-received or unavailable batches.

FIFO may remain in Chapter 2 only when it accurately describes findings from cited literature. It must not be presented as the implemented inventory policy.

Every planned test receives a unique test ID. Requirement IDs must be copied exactly from the latest report. If no exact requirement applies, write **Requirement mapping needed** instead of creating a new requirement ID.

Use these readiness and result labels:

- **Implemented:** the required executable function exists.
- **Partial:** only part of the workflow exists, such as tables without the business service.
- **Pending implementation:** the executable feature is missing.
- **Not executed:** the planned test has not been run.
- **Pass/Fail:** use only after the test has been executed and its actual result has been observed.

Implementation evidence explains how the system was built. Testing evidence records an input or action, the observed output and whether it matched the expected result. A code screenshot or database definition alone does not prove that a test passed.

## 2. Current implementation position

This review position was recorded on 31 October 2026. Recheck it whenever the code changes.

| Area | Current position | Next work |
|---|---|---|
| Database foundation | The plan records 29 application tables, one reporting view, constraints, indexes, RLS policies, setup SQL and verification scripts. | Re-run verification on the current test database and keep dated results. |
| User and access management | Backend token authentication, profile retrieval and a generic role guard exist. Temporary manager/admin probe routes are present. | Complete real user workflows, Flutter login/profile/logout, user administration and final-active-administrator protection. Recheck the health-route order and role error wording. |
| Demand prediction | Prediction and model-storage tables exist. | Implement Python/FastAPI prediction, cold start, confidence, feature preparation, RF/LR evaluation and controlled model activation. |
| Inventory and recommendations | Catalogue, recipe, batch and production-decision tables exist. A FEFO verification query/index exists. | Implement shared-ingredient planning, decision confirmation and actual FEFO deduction service. |
| POS simulation | Storage tables and arithmetic constraints exist. | Implement the manager-confirmed simulation workflow as one atomic transaction with duplicate protection and rollback. |
| Leftover management | Charity, donation and waste tables exist. | Implement manager-confirmed allocation, active-charity validation, status updates and concurrency protection. |
| Reporting | Result fields, price snapshots and a time-slot view exist. | Implement dashboards, consumed-batch ingredient costing, weekly reports and PDF/CSV exports. |
| Notifications | Notification, preference, token and delivery tables plus recipient-read RLS exist. | Implement Node notification services, mark-read API, Flutter Realtime subscription and FCM submission. |
| Administration | Settings, roles, audit and model tables exist. | Implement settings, account, charity, model and audit workflows. |
| Flutter application | The reviewed plan records the starter counter application only. | Replace it with the bakery login and role-based application screens. |

Do not use the database schema as proof that a complete workflow exists. For example, a FEFO index does not consume inventory, and a uniqueness constraint does not by itself provide complete POS idempotency.

## 3. Recommended Chapter 5 structure

| Section | Content |
|---|---|
| 5.1 Introduction | State that the chapter explains the implemented system and the testing performed against the requirements. |
| 5.2 Development environment and configuration | Flutter, Node.js/TypeScript, Python/FastAPI, Supabase, REST/JSON, authentication, environment variables, database security and deployment settings. |
| 5.3 System implementation | Selected important code and configuration organised by functionality. |
| 5.4 Testing methodology | Unit, database, API integration, Android system, failure-recovery, performance, model evaluation and UAT methods. |
| 5.5 Functional and integration test results | Test-case tables grouped by functional module. |
| 5.6 Model evaluation | Dataset, chronological split, RF/LR comparison, metrics and candidate-model decision. |
| 5.7 Non-functional testing | Performance, security, reliability, compatibility, responsive layout and UAT results. |
| 5.8 Chapter summary | Summarise demonstrated coverage, defects, retests, limitations and remaining work. |

Chapter 5 should describe the final implementation by functionality. It should not be a chronological diary of every coding step.

## 4. Development and evidence workflow

Apply this workflow to each milestone:

1. Implement the complete bounded feature.
2. Run build, static-analysis and developer checks.
3. Execute the relevant planned tests.
4. Fix observed defects.
5. Retest the corrected behaviour.
6. Capture only the selected implementation and testing evidence.
7. Record the actual result and Pass/Fail status.
8. Continue to the next milestone.

Keep evidence while coding, but do not interrupt implementation to create report screenshots for incomplete features.

## 5. Implementation milestones and screenshot checklist

### Milestone 1: Complete user and access management

**Requirements:** BR-UAM-01, BR-UAM-02, BR-UAM-03, FR-UAM-01 to FR-UAM-05, NFR-SEC-01, NFR-SEC-02, NFR-SEC-03 and NFR-SEC-05.

**Implement:**

- Correct backend route ordering and error wording where still applicable.
- Keep token verification and profile-status checks on protected routes.
- Complete Flutter login, own-profile view/update and logout.
- Implement administrator account/role management.
- Prevent deactivation or removal of the final active administrator.
- Replace temporary role probes with permission checks on real business routes when those routes exist.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-UAM-01 | Backend access workflow is final | Authentication middleware and active-profile validation, with filename and function visible | Token verification and active-user validation |
| I-UAM-02 | Real protected routes exist | Role guard and one manager-only plus one administrator-only route | Role-based access control implementation |
| I-UAM-03 | Flutter workflow works | Login/profile screen and secure session handling code, without credentials or tokens | Flutter authentication and profile workflow |

**Planned tests:** T-UAM-01 to T-UAM-08 in Section 6.

### Milestone 2: Implement demand prediction and model management

**Requirements:** BR-DP-01 to BR-DP-05, FR-DP-01 to FR-DP-12 and NFR-ACC-01 to NFR-ACC-08.

**Implement:**

- Select one validated record per category/date with origin priority: actual, imported, then simulation-generated.
- Use `units_sold` as the target and prevent future-data leakage.
- Use Random Forest only with at least 30 distinct valid days and a valid active model.
- Use the mean of available valid records for cold start; use the configured base only when none exist.
- Store cold-start confidence as null and display a heuristic warning.
- Apply the report confidence formula to Random Forest tree predictions.
- Compare RF and Linear Regression on the same chronological holdout.
- Require administrator review and explicit activation; reject a candidate with higher MAE on the same holdout.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-DP-01 | Prediction unit tests pass | History selection, cold-start branch and model branch | Prediction-mode selection and cold-start handling |
| I-DP-02 | Confidence tests pass | Confidence calculation and low-confidence threshold | Random Forest confidence calculation |
| I-DP-03 | Model lifecycle works | Training/evaluation result and activation guard | Candidate-model evaluation and controlled activation |

**Planned tests:** T-DP-01 to T-DP-07.

### Milestone 3: Implement inventory and smart production recommendations

**Requirements:** BR-INV-01 to BR-INV-06 and FR-INV-01 to FR-INV-12.

**Implement:**

- Complete category, ingredient, recipe, restocking and movement services.
- Build a temporary planning balance from valid inventory.
- Subtract confirmed but unprocessed commitments first.
- Process unconfirmed categories by display order and reduce the temporary balance after each allocation.
- Revalidate the complete plan when a manager confirms or changes a quantity.
- Replace an earlier decision quantity instead of counting it twice.
- Deduct stored batches only when official POS simulation begins.
- Implement FEFO using `expiry_date`, `received_date`, then `id`, all ascending.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-INV-01 | Shared-stock tests pass | Temporary balance and combined-requirement calculation | Shared-ingredient production feasibility |
| I-INV-02 | Confirmation tests pass | Decision validation and recalculation of affected recommendations | Production-decision confirmation and revalidation |
| I-INV-03 | Actual deduction works | FEFO query/service and movement creation | FEFO batch deduction by expiry, receipt and ID |

**Planned tests:** T-INV-01 to T-INV-06.

### Milestone 4: Implement atomic POS simulation

**Requirements:** BR-POS-01 to BR-POS-07, FR-POS-01 to FR-POS-08, BR-INV-05, BR-INV-06, NFR-REL-01 and NFR-REL-04.

**Implement:**

- Require a stored prediction and confirmed manager decision.
- Reject client production overrides.
- Revalidate inventory and lock the required records.
- Complete FEFO deduction, inventory logs, production, sales, daily results and simulation-generated history in one transaction.
- Prevent the same decision from being processed twice.
- Roll back every related change when any step fails.
- Use the stored prediction as the baseline without applying weather or holiday multipliers again.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-POS-01 | Successful integration test passes | Transaction/RPC boundary, locks and processed-decision guard | Atomic POS simulation transaction |
| I-POS-02 | Android workflow works | Confirmed production, simulation start and result screen | Manager-initiated POS simulation |

**Planned tests:** T-POS-01 to T-POS-05.

### Milestone 5: Implement leftover, donation and waste management

**Requirements:** BR-LDW-01 to BR-LDW-03 and FR-LDW-01 to FR-LDW-07.

**Implement:**

- Display leftovers from completed simulations.
- Require explicit manager confirmation for donation or waste.
- Validate positive quantities, active charity partners and disposal reasons.
- Prevent combined allocation from exceeding remaining leftovers under concurrent requests.
- Maintain donation status and unallocated balance consistently.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-LDW-01 | Allocation tests pass | Locked balance validation and atomic allocation update | Controlled donation and waste allocation |
| I-LDW-02 | Android workflow works | Leftover balance and confirmed donation/waste action | Leftover management interface |

**Planned tests:** T-LDW-01 to T-LDW-04.

### Milestone 6: Implement dashboards, reports and exports

**Requirements:** BR-RPT-01 and FR-RPT-01 to FR-RPT-06, plus NFR-ACC-06.

**Implement:**

- Calculate prediction error as `units_sold - predicted_units_sold`.
- Distinguish leftover quantity from actual discarded waste.
- Calculate ingredient cost from quantities consumed from FEFO-selected batches and their recorded unit costs.
- Calculate revenue from transaction price snapshots.
- Support daily, weekly, monthly/custom and category filters where specified.
- Make UI, CSV and PDF use the same filters and calculations.
- Label simulation-generated information clearly.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-RPT-01 | Calculation tests pass | Shared reporting calculation service, including batch cost | Operational and financial report calculations |
| I-RPT-02 | Export comparison passes | Report screen beside matching CSV/PDF totals | Consistent report display and export |

**Planned tests:** T-RPT-01 to T-RPT-04.

### Milestone 7: Implement notifications

**Requirements:** BR-ALT-01 and FR-ALT-01 to FR-ALT-04.

**Implement:**

- Create recipient-specific notification records.
- Apply notification-type preferences.
- Use recipient-only Supabase Realtime reads for foreground notifications.
- Perform mark-read through Node.js.
- Submit eligible background notifications through FCM using active recipient tokens.
- Store delivery status accurately; provider submission is not automatically delivery or reading.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-ALT-01 | Isolation tests pass | Recipient policy and Node mark-read route | Recipient-scoped notification access |
| I-ALT-02 | Device test passes | Preference/token checks and delivery-state update | Realtime and push-notification delivery workflow |

**Planned tests:** T-ALT-01 to T-ALT-04.

### Milestone 8: Complete administration and full integration

**Requirements:** FR-ADM-01 to FR-ADM-04, BR-UAM-03, NFR-DAT-03 and the applicable security/maintainability requirements.

**Implement:**

- Bakery and system settings with type/range validation.
- Charity, external-service and model settings.
- Audit records for important successful and failed operations.
- Final-active-administrator protection.
- Role-specific Flutter navigation and integrated end-to-end workflows.

**Later implementation screenshots:**

| Evidence ID | Capture after | What to show | Suggested caption |
|---|---|---|---|
| I-ADM-01 | Settings tests pass | Typed validation and audit write | Protected settings and audit trail |
| I-ADM-02 | Full app works | Manager and administrator navigation screens | Role-specific Android navigation |

**Planned tests:** T-ADM-01 to T-ADM-03 and all NFR tests.

## 6. Functional test checklist

All tests begin with **Actual result: Not executed** and **Status: Not executed**. When writing Chapter 5, use columns: Test ID, Requirement ID, Preconditions, Steps/Input, Expected Result, Actual Result, Pass/Fail and Evidence ID.

### 6.1 User and access management

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-UAM-01 | FR-UAM-01, FR-UAM-03, NFR-SEC-01 | Sign in with a valid active manager and retrieve own profile. | Login succeeds and only the authenticated profile is returned. |
| T-UAM-02 | BR-UAM-01, NFR-SEC-01 | Access a protected route without a token and with an invalid/expired token. | Requests are rejected without returning protected data. |
| T-UAM-03 | BR-UAM-02, FR-UAM-04, NFR-SEC-02 | Use manager and administrator accounts on each other's protected operations. | Each role can access only its permitted functions. |
| T-UAM-04 | FR-UAM-03, NFR-DAT-01 | Update permitted profile fields and attempt to change own role/status. | Permitted fields update; protected fields are rejected. |
| T-UAM-05 | FR-UAM-02 | Log out and reopen a protected screen. | Session is cleared and authentication is required again. |
| T-UAM-06 | FR-UAM-05, BR-UAM-03 | Attempt to deactivate the final active administrator. | Operation is rejected with no partial update. |
| T-UAM-07 | NFR-SEC-05 | Inspect client build and repository for server secrets. | No privileged key or secret is exposed. |
| T-UAM-08 | NFR-REL-03 | Simulate temporary authentication-service failure and retry. | No bypass occurs; understandable error and successful retry are provided. |

### 6.2 Demand prediction and model lifecycle

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-DP-01 | FR-DP-01, BR-DP-04 | Provide competing data origins for the same category/date. | One validated record is selected by origin priority and `units_sold` remains the target. |
| T-DP-02 | FR-DP-06, FR-DP-07 | Test 29 valid days, 30 valid days with an active model, and 30 days without one. | Correct cold-start/model mode is selected. |
| T-DP-03 | FR-DP-07, NFR-ACC-08 | Test available-history and no-history cold starts. | Average valid history is used first; configured base is fallback; confidence is null with heuristic warning. |
| T-DP-04 | FR-DP-08, NFR-ACC-08 | Test confidence formula and values around the 75% threshold. | Stored/displayed confidence and Low Confidence label match the report formula and boundary. |
| T-DP-05 | FR-DP-03, FR-DP-04, FR-DP-05 | Generate next-day predictions with valid and unavailable context services. | Correct target-date context is used; controlled retry/fallback behaviour is shown. |
| T-DP-06 | FR-DP-09 to FR-DP-12, NFR-ACC-01 to NFR-ACC-05 | Train RF/LR on the same chronological data and attempt to activate a worse candidate. | Metrics are stored; higher-MAE candidate is rejected; active model is retained. |
| T-DP-07 | NFR-ACC-02, NFR-ACC-03, NFR-ACC-07 | Evaluate fixtures containing zero actual sales and simulation data. | MAE/RMSE include zero rows; MAPE excludes them; simulation-based results are labelled. |

### 6.3 Inventory and recommendations

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-INV-01 | BR-INV-01, FR-INV-07, FR-INV-08 | Generate recommendations with complete and missing recipe/prediction data. | Valid recommendation is generated; missing prerequisites are identified. |
| T-INV-02 | BR-INV-02, FR-INV-07 | Two categories share insufficient stock. | Temporary balance prevents repeated allocation of the same ingredient. |
| T-INV-03 | BR-INV-03, FR-INV-10 to FR-INV-12 | Accept, reduce and override recommendations with valid/invalid reasons. | Only feasible, correctly reasoned decisions are saved. |
| T-INV-04 | BR-INV-04, FR-INV-09 | Outstanding commitments exceed valid inventory. | Shortage and reduced-production/restocking options are shown. |
| T-INV-05 | BR-INV-05, FR-INV-05, FR-INV-06 | Use batches where receipt order conflicts with expiry order and include date/ID ties. | Valid batches are consumed by expiry, received date and ID; invalid batches are excluded. |
| T-INV-06 | BR-INV-06, FR-POS-08 | Retry a processed production decision. | Inventory is not deducted more than once. |

### 6.4 POS simulation

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-POS-01 | BR-POS-01, FR-POS-01, FR-POS-02 | Start without stored prediction or confirmed manager decision. | Simulation is blocked without database changes. |
| T-POS-02 | BR-POS-02 to BR-POS-07, FR-POS-03 to FR-POS-07 | Run a valid deterministic simulation. | Sold, lost sales, estimated demand, revenue, leftovers and simulation history are correct. |
| T-POS-03 | BR-POS-07 | Verify stored prediction context is not multiplied again. | Simulation uses the stored prediction baseline once. |
| T-POS-04 | BR-INV-06, FR-POS-08 | Submit duplicate or concurrent simulation requests. | Only one transaction and one FEFO deduction are committed. |
| T-POS-05 | NFR-REL-01, NFR-REL-04 | Inject failure at several transaction stages and retry. | Every failed attempt rolls back fully; retry revalidates and commits once. |

### 6.5 Leftover, donation and waste

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-LDW-01 | FR-LDW-01, FR-LDW-02 | Open leftovers from a completed simulation. | Correct leftover and suggested action are displayed. |
| T-LDW-02 | BR-LDW-01 to BR-LDW-03, FR-LDW-03 to FR-LDW-05 | Record valid/invalid donation and waste quantities. | Valid confirmed allocations succeed; excessive/invalid input is rejected. |
| T-LDW-03 | BR-LDW-01, NFR-REL-01 | Submit concurrent allocations exceeding the balance. | Combined allocation never exceeds the leftover; failures leave no partial records. |
| T-LDW-04 | FR-LDW-06 | Apply valid and invalid donation-status transitions. | Valid progress is stored without a second allocation; invalid transitions are rejected. |

### 6.6 Reporting and dashboard

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-RPT-01 | FR-RPT-04, FR-RPT-05, NFR-ACC-06 | Verify prediction error, estimated demand, leftovers and waste. | Error equals sold minus predicted; leftover and discarded waste remain distinct. |
| T-RPT-02 | BR-RPT-01, FR-RPT-01 | Calculate revenue, FEFO batch cost and gross profit; change current master prices afterward. | Historical report continues using transaction prices and consumed batch costs. |
| T-RPT-03 | FR-RPT-02, FR-RPT-03 | Apply date, period and category filters, including empty data. | Correct data is aggregated once and empty results are explained. |
| T-RPT-04 | FR-RPT-06 | Export the selected report to PDF and CSV. | UI, PDF and CSV use identical filters and calculations and show simulation labels. |

### 6.7 Notifications

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-ALT-01 | FR-ALT-01, FR-ALT-02 | Generate each supported event for two recipients. | Only relevant authorised recipients see the notification. |
| T-ALT-02 | FR-ALT-03, NFR-SEC-02 | Read/mark own and another user's notification. | Own operation succeeds through Node; foreign access is rejected. |
| T-ALT-03 | BR-ALT-01, FR-ALT-04 | Test enabled/disabled preference and valid/invalid device tokens. | Only eligible tokens are submitted; skipped reasons are stored. |
| T-ALT-04 | FR-ALT-04, NFR-REL-03 | Test successful submission, provider failure and device receipt. | Submission, delivery, failure and read states are not confused. |

### 6.8 Administration

| Test ID | Requirement ID | Planned test | Expected result |
|---|---|---|---|
| T-ADM-01 | FR-ADM-01, FR-ADM-02 | Save valid and invalid typed settings as admin and manager. | Valid admin setting is stored; invalid/unauthorised changes are rejected. |
| T-ADM-02 | FR-ADM-03, NFR-SEC-05 | Configure service references without storing secrets in client-visible settings. | Non-secret configuration is available; secrets remain protected. |
| T-ADM-03 | FR-ADM-04, NFR-DAT-03 | Perform successful and rejected important operations. | Audit records contain actor, action, target, outcome and timestamp and cannot be edited by normal users. |

## 7. Database verification plan

Run the existing SQL verification scripts only in the test project and keep their dated outputs. Scripts that insert fixtures inside a transaction are data-changing during execution even if they later roll back.

Use one test ID per script or suite, such as `T-DB-01`, `T-DB-02` and so on. Map each suite to the exact requirements it verifies. Keep the full assertion results in the appendix. In the main Chapter 5, include:

- One representative schema/RLS result.
- One representative constraint or rollback result.
- A concise table listing all executed SQL suites and their Pass/Fail outcomes.

Do not describe a reference `ORDER BY` query as proof that the application consumed stock. FEFO compliance requires an actual service/RPC test with before-and-after batch and movement records.

## 8. Model evaluation plan

Keep model evaluation separate from ordinary functional testing.

1. Freeze a dataset manifest containing the date range, category IDs, selected record IDs, data origins, exclusions and version/hash.
2. Select one valid observation per category/date using the required origin priority.
3. Arrange training, optional validation and final testing periods chronologically.
4. Fit RF and LR on identical training observations and evaluate identical later test observations.
5. Calculate MAE and RMSE using all test rows. Calculate MAPE only where actual units sold are above zero. Calculate R² and state when it is undefined.
6. Label results containing simulation-generated observations as simulation-based performance.
7. Compare candidate and active models on the same holdout. Reject the candidate when its MAE is higher.
8. Store row-level actual and predicted values so calculations can be checked.

Use one model-comparison table and one selected screenshot of the evaluation/activation result. Put detailed row-level predictions in an appendix or separate evidence file.

## 9. Non-functional testing plan

| Test ID | Requirement ID | Planned test and acceptance target |
|---|---|---|
| T-NFR-01 | NFR-PER-01 | Under the report's reference environment, at least 95% of specified screen requests with no more than 50 records complete within three seconds. |
| T-NFR-02 | NFR-PER-02 | Prediction and production recommendation each complete within 15 seconds for up to 20 categories and 365 records per category. |
| T-NFR-03 | NFR-PER-03 | A 12-hour simulation and a seven-day report each complete within 30 seconds for up to 20 categories. |
| T-NFR-04 | NFR-SEC-03 to NFR-SEC-05 | Review password handling, TLS 1.2+ deployment communication and absence of exposed secrets. |
| T-NFR-05 | NFR-REL-01 to NFR-REL-04 | Combine rollback, active-model retention, external-service retry and nonnegative-quantity results from the relevant module tests. |
| T-NFR-06 | NFR-USA-03, NFR-COM-01 | Verify all primary screens at 360 x 640 dp through 412 x 915 dp on Android 10 or later without overlap, clipping or required horizontal scrolling. |
| T-NFR-07 | NFR-USA-01, NFR-USA-02, NFR-USA-04 | Conduct independent UAT and calculate the percentage completing login, prediction, confirmation, simulation and leftover recording without assistance or a task-blocking problem. Target at least 80%. |
| T-NFR-08 | NFR-MAI-01 to NFR-MAI-03, NFR-COM-02, NFR-DAT-01 to NFR-DAT-03 | Review layering, configuration, naming, JSON contracts, timestamps, validation and audit information, supported by selected integration results. |

Record the actual device/emulator, Android version, RAM, viewport, network condition, backend/database versions, dataset size, cache state, repetitions and timing method. Do not use API-only timings to claim rendered-screen performance.

## 10. Evidence and report-size rules

- Aim for approximately 8 to 12 important implementation figures across the final system.
- Use one or two representative test screenshots per module when useful.
- Document all distinct executed cases in tables, even when they share one evidence screenshot.
- Put full terminal logs, SQL grids, model row-level results and repeated screenshots in appendices or separate evidence files.
- Show filenames and function names in code evidence. Use approximately 15 to 35 relevant readable lines.
- Capture terminal evidence only after the status code and response body appear.
- Hide passwords, access/refresh tokens, service-role keys, JWT secrets, FCM credentials, database connection strings, recovery links and personal information.
- Keep failed evidence and link it to the later retest. Do not overwrite the failure history.
- Never create or reconstruct a screenshot that was not captured from the actual implementation or test.

Recommended test-case table:

| Test ID | Requirement ID | Preconditions | Steps/Input | Expected Result | Actual Result | Pass/Fail | Evidence ID |
|---|---|---|---|---|---|---|---|

## 11. Immediate implementation priority

The next milestone is **complete User and Access Management end to end** because the database foundation and part of the backend authentication layer already exist, while the Flutter client remains a starter application.

### Code next

1. Recheck and correct the `/api/health` route position and current error wording.
2. Finalise authentication/profile/logout endpoints and session behaviour.
3. Implement Flutter login, own-profile and logout screens.
4. Implement role-based Flutter navigation.
5. Implement administrator account/role management and final-active-administrator protection.
6. Replace temporary permission probes with tests on real protected operations as those operations are introduced.

### Test after implementation

Execute T-UAM-01 to T-UAM-08. Run type checking/build checks first, then API integration tests, Flutter widget/integration tests and final Android manual checks.

### Retain for Chapter 5

- One readable code figure showing token verification, active-profile validation and the role guard.
- One combined result figure or compact evidence table showing permitted and rejected access for both roles.
- One Flutter figure showing the completed login/profile workflow.

Do not begin demand-prediction evidence capture until its executable services exist and its planned tests have been run.