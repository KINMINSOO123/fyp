# Module 5: Leftover Management and Reporting — Detailed Plan

**Reconciled:** 2026-10-11 using the latest `RSW_SooKinMin_Project1 (1).docx`, Sections 3.4–3.6, 4.5.3–4.5.4, 4.6–4.9, including Tables 4.25–4.27. **Status:** design and future verification only. The repository currently has a Flutter starter and plans; none of the classes, endpoints, DTO sketches or workflows below is a claim of implemented functionality. The [report mirror](../../RSW_SooKinMin_Project1.docx.md) is a navigation aid.

## 1. Functional scope and dependencies

Technical Module 5 covers functional modules 5 **Leftover, Donation and Waste Management** and 6 **Reporting and Dashboard**, with charity administration under functional module 8 and event integration under module 7. It presents the outputs of functional modules 2–4 without moving prediction or operational business rules into Flutter. The technical numbering remains a build sequence, not an alternative functional taxonomy.

Module 0 supplies the normalized schema; Module 1 supplies protected Controllers, Services, Repos, profile-role enforcement, settings, audit and recipient notifications. Module 2 supplies stored predictions and evaluation metadata. Module 3 supplies recommendations and decisions. Module 4 atomically produces completed DailyResults, transaction unit-price snapshots, exact consumed-batch movements/cost snapshots and validated simulation-origin history. Reads must not observe a partly committed simulation.

The single-bakery Android design uses configured active categories, with up to 20 in the reference workload. Seed examples of four bread categories and five ingredients are not fixed UI or reporting limits. Automatic donation, background scheduling, customer ordering/payment and real POS or delivery-platform integration remain outside scope.

## 2. Layered responsibilities and Views

| Boundary | Proposed responsibility |
|---|---|
| `LeftoverManagementController` | Validate request transport and permissions; delegate read, recommendation, allocation and status actions |
| `LeftoverManagementService` | Check completed-result eligibility, quantity/partner/reason rules, manager confirmation, remaining balance and status transition |
| `DailyResultRepo`, `DonationRepo`, `WasteRecordRepo` | Execute result locking and allocation inserts/balance changes using the same transaction/RPC context |
| `CharityPartnerController -> CharityPartnerService -> CharityPartnerRepo` | Administrator-managed active partner catalogue and retained historical links |
| `DashboardController -> DashboardService -> ReportRepo` | Compose permitted summaries; a read does not trigger operational processing |
| `ReportController -> ReportService -> ReportRepo` | Filter and calculate one consistent report model for display/export |
| `ReportExportAdapter` | Render the calculated report as supported CSV/PDF without querying or changing source records |
| `AuditService`, `NotificationService` | Audit mutations; notify authorized recipients of surplus/status/error events after successful business commit |

`ManagerDashboardView` presents prediction, production decision, simulation and leftover actions with explicit prerequisites. `AdministratorDashboardView` presents permitted reports and administration links; it does not expose manager action buttons. `LeftoverManagementView` presents confirmed leftovers and forms; `DonationStatusView` presents history and permitted transitions; `CharityPartnersView` is administrator-only; `ReportsView` contains period/category filters and manual export. Both roles retain `ProfileView`, `NotificationsView` and personal preferences from Module 1.

Use `ApiClient` for protected Node requests. Flutter uses Supabase Authentication, recipient-scoped Supabase Realtime for notification events and FCM background notification reception as explicit report exceptions; these do not grant direct ordinary-table CRUD. Express router modules remain separate from Controller classes.

## 3. Normalized entities and transport contracts

The allocation chain is `DailyPrediction -> ProductionDecision -> DailyProduction -> DailyResult -> Donation/WasteRecord`. Unique prediction/decision/production/result references enforce at most one applicable operational row at each step. Donation and waste category/date are resolved from `daily_result_id`; allocations do not carry another independently editable category reference. There is no persisted `LeftoverRecord` or `SimulationRun` entity.

```ts
// Proposed API types; identifiers are validated UUIDs and quantities positive integers.
type RecordDonationRequest = {
  dailyResultId: string;
  quantity: number;
  charityPartnerId: string;
};
type RecordWasteRequest = {
  dailyResultId: string;
  quantity: number;
  disposalReason: string;
};
type DonationStatus = 'PENDING' | 'COLLECTED' | 'COMPLETED' | 'CANCELLED';
type DonationStatusRequest = { status: DonationStatus };
type LeftoverSummary = {
  dailyResultId: string;
  breadCategoryId: string; // derived from DailyResult, never a second allocation FK
  resultDate: string;
  produced: number;
  unitsSold: number;
  leftover: number;
  donated: number;
  wasted: number;
  remainingUnallocated: number;
  dataOrigin: 'SIMULATION_GENERATED';
};
```

The transport schema must reject unknown authority fields such as `confirmedBy`, role and asserted availability. Node derives the manager from JWT plus active stored profile and recalculates feasibility under database locks. A body flag claiming confirmation is not an authorization mechanism; the dedicated mutation follows an explicit confirmation UI and server authorization.

Use canonical snake_case storage fields such as `daily_result_id`, `charity_partner_id`, `confirmed_by` and `disposal_reason`; map API fields explicitly in Repos. Reported `remainingUnallocated` maps to the canonical DailyResult remaining-allocation value/derived invariant, not an independent table. Both quantities and source provenance remain visible in returned DTOs.

## 4. Endpoints and role checks

| Method/path | Permission | Service operation |
|---|---|---|
| `GET /api/leftovers?date=...&breadCategoryId=...` | Both active roles, permitted read | `LeftoverManagementService.listSummaries` from completed results |
| `GET /api/leftovers/:resultId/recommendation` | Manager | `recommendAction`; no persistence/allocation |
| `POST /api/donations` | Manager | `recordDonation` with active partner and explicit confirmation |
| `POST /api/waste-records` | Manager | `recordWaste` with reason and explicit confirmation |
| `PATCH /api/donations/:id/status` | Manager | `updateDonationStatus`; server checks transition, records update time/audit |
| `GET/POST /api/admin/charity-partners`; `PATCH /api/admin/charity-partners/:id` | Administrator | List/create/update/deactivate; retain referenced partners |
| `GET /api/dashboard?date=...&breadCategoryId=...` | Both active roles | `DashboardService.getSummary`; role-permitted DTO |
| `GET /api/reports?period=WEEKLY&startDate=...&endDate=...&breadCategoryId=...` | Both active roles | `ReportService.generate`; selected period/category |
| `GET /api/reports/export` with the same filters and `format=CSV` or `PDF` | Both active roles | Same `ReportService` calculation, then `ReportExportAdapter` |

Report filters may select a date, supported reporting period or explicit date range and one category or all categories. Validate invalid/inverted periods and pagination; seven-day reports are supported. Explicit ranges use inclusive bakery-local dates and unambiguous timestamps in exports. The selected range, not a hard-coded calendar-week assumption, defines a weekly request. Backend validation prevents one invalid client query from changing underlying records.

Manager forms receive only eligible active charity choices through the leftover response/read contract; this does not expose the administrator charity endpoints. System Administrators may review reports but cannot use manager-only allocation or status mutation endpoints. Backend permission tests must verify this even if the Flutter UI hides the button.

## 5. Transactional leftover allocation

`LeftoverManagementService.recommendAction` reads completed leftovers and configured handling rules. It returns a suggestion and reason; it cannot create a donation/waste record, choose a charity on behalf of the manager or schedule an allocation. If recommendation data are unavailable, explain the issue and allow a permitted manual choice with normal validation. With no completed result or no remaining quantity, prevent allocation.

The mutation sequence is proposed as one Node-owned database transaction/RPC:

1. Validate JWT, active manager role, UUIDs, positive integer quantity and required partner/reason input.
2. Lock the referenced DailyResult and inspect its completed production/simulation links. Derive category/date from that row.
3. Read committed donation/waste allocations under the same result lock; recompute remaining quantity and verify the stored/cache invariant.
4. For donation, lock or otherwise consistently validate that the selected charity is active at commit. For waste, validate a nonblank disposal reason.
5. Reject the request if it exceeds remaining quantity. Insert the donation (`PENDING`) or waste record with the authenticated manager and timestamp.
6. Update remaining unallocated quantity and audit in the same transaction. Commit all or roll back all. Only then deliver eligible recipient notification events.

```text
leftover = produced - units_sold
remaining_unallocated = leftover - sum(committed donation quantities)
                                - sum(committed waste quantities)
leftover = donated + wasted + remaining_unallocated
```

Locking the common result serializes competing donation/waste requests even if they target different allocation tables. If leftover is 10, simultaneous donation of 7 and waste of 6 cannot both succeed. Each operation must re-read the balance after acquiring the lock; a client-displayed balance is insufficient. Positive quantity validation excludes zero/negative requests, and all source quantity totals remain nonnegative.

The client retains form inputs after a network error and refreshes the result/history before retrying an uncertain mutation; it must not silently issue a second allocation after an unknown commit outcome. The canonical plan does not add idempotency tables to solve this. Audit and record IDs allow the UI to inspect the completed request. Any future retry-key design must be specified explicitly before automatic retry is enabled.

## 6. Donation status and unresolved cancellation policy

Canonical donation status values are `PENDING`, `COLLECTED`, `COMPLETED`, `CANCELLED`. The planned normal workflow is manager-recorded `PENDING -> COLLECTED -> COMPLETED`, with explicit confirmation, server validation, updated timestamp and audit. A status update records progress; it does not create another donation or subtract the quantity again. Ordinary progress does not change the allocation balance.

| Retired donation term | Current donation term |
|---|---|
| `RECORDED` | `PENDING` |
| `PICKED_UP` | `COLLECTED` |
| `DELIVERED` | `COMPLETED` |

This mapping concerns donation terminology only. `notification_deliveries` still uses `DELIVERED` for evidenced device delivery. The original donation row and history are retained; no automatic donation is triggered by a status update.

The report identifies cancellation but does not define whether/when a cancelled donation releases its quantity, whether collected/completed records can be cancelled, or how release/reallocation and historical totals interact. **Open decision:** define the permitted cancellation transitions and an atomic accounting/audit policy before enabling the `CANCELLED` mutation. The enum can represent the concept, but current implementation guidance must reject an unsupported cancellation request with an explanatory message. Do not silently release quantities, delete the donation, or invent an allocation reversal rule. A manager cancelling an unsubmitted form remains a separate no-change UI action.

Donation-status events use `NotificationService` with intended recipients, type preferences and tracked delivery; they do not broadcast all donation data to all staff.

## 7. Dashboard and confidence presentation

`DashboardService` composes committed data and `PendingActionService` state; reading or refreshing the dashboard never generates prediction, confirms production, starts simulation, retrains a model or allocates leftovers. Display dates and prerequisites clearly. Current date is the simulation default; next-day prediction remains an explicit manager action.

| View area | Display and action responsibility |
|---|---|
| Prediction/planning | Stored predicted units sold, mode, confidence where applicable, factors, joint ingredient limits, confirmation/override reason |
| Sales/results | Confirmed production, simulated sold/lost-sales/estimated-demand/leftover values, transaction detail, date and simulation label |
| Leftovers | Donated, discarded waste and remaining unallocated as separate quantities; eligible manual actions and donation status |
| Inventory | Permitted stock/shortage/expiry information; administrator maintenance navigation; FIFO means receipt order |
| Model analytics | Origin-labelled MAE/RMSE/MAPE/R² and dataset periods; administrator model-management link |
| Finance | Revenue, actual consumed-batch ingredient cost, gross profit and defined/null percentages; reporting-only |
| Notifications | Recipient-only events with personal read state; foreground Realtime and preference-gated background FCM |

Proposed Flutter confidence formatting keeps nullability explicit:

```dart
// Design example only. API decoding validates the mode-specific contract first.
String confidenceLabel(String predictionMode, double? confidence, double threshold) {
  if (predictionMode == 'COLD_START') return 'Cold start — low-confidence heuristic';
  if (predictionMode != 'MODEL' || confidence == null || !confidence.isFinite ||
      confidence < 0 || confidence > 100) {
    throw FormatException('Invalid prediction confidence');
  }
  final value = '${confidence.toStringAsFixed(1)}% tree agreement';
  return confidence < threshold ? 'Low Confidence: $value' : value;
}
```

MODEL responses require a numerical confidence and applicable model version. COLD_START responses require `confidence = null`, no model version and a low-confidence heuristic label. Node/Python own calculation; Flutter does not manufacture a percentage. Confidence is `100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))`, with initial low-confidence threshold 75%. This is tree agreement, not an accuracy probability or evidence of improvement. Comparisons/feature importance only describe the applicable model and must not imply that a heuristic used a trained model.

## 8. Shared report model and formulas

`ReportService` produces one report model used by dashboard cards, detail tables and exports. For a single day/category the report uses validated stored operational results; comparable prediction-performance analysis matches selected validated `DailySalesRecord.unitsSold` to the stored prediction. Select actual, then imported, then simulation history for each category/day and keep its provenance. `estimatedDemand` remains analytical and cannot replace the model's units-sold target.

| Metric | Calculation |
|---|---|
| Estimated demand | `units_sold + lost_sales` |
| Leftovers | `produced - units_sold` |
| Signed sales prediction error | `units_sold - predicted_units_sold` |
| Sales fulfilment (%) | `units_sold / estimated_demand * 100` |
| Leftover rate (%) | `leftover / produced * 100` |
| Discarded waste rate (%) | `wasted / produced * 100` |
| Revenue | `sum(sales_transactions.quantity * sales_transactions.unit_price)` using captured sale price |
| Ingredient cost | Sum of consumed FIFO batch quantities times their historical unit-cost snapshots, converting grams/kg consistently |
| Gross profit | `revenue - ingredient_cost` |
| Gross-profit margin (%) | `gross_profit / revenue * 100` |

For period ratios, aggregate numerators and denominators before dividing; do not average category/daily percentages. A zero denominator yields a null numeric value and **Not Applicable** on screen/PDF. CSV preserves a blank/null numeric cell with a corresponding applicability label; do not export an invented zero percentage. Signed prediction error and negative gross profit/margin remain permitted. Donated or still-unallocated leftovers are not discarded waste.

Financial cost includes all ingredients consumed to produce the confirmed quantity, including units later donated or discarded. `IngredientCostService.calculateFromMovements` from Module 4 creates or verifies the stored production cost using exact FIFO batch movements and their cost snapshots; `ReportRepo` reads that committed history. Current ingredient master prices cannot rewrite historical cost.

Concrete planned fixture: consume 2 kg from an older batch priced RM3/kg and 1 kg from a later batch priced RM5/kg. Ingredient cost is RM11. With revenue RM8, gross profit is -RM3 and margin is -37.5%. A later master-price change to RM10/kg leaves this history unchanged. FIFO batch receipt order is `received_date, id`, excluding inactive/expired batches; expiry-first selection would change the cost and is not this report's algorithm.

Detailed sales transactions provide time-slot rows; DailyResult contains the consolidated daily totals. Pick one level for each aggregate, never add both. Unique prediction/decision/production/result links avoid fan-out; aggregate allocation and transaction subqueries separately before joining to prevent multiplication of totals. A weekly report sums the selected seven days/categories once each.

Prediction-performance displays MAE, RMSE, MAPE and R² with origin/dataset labels. Zero actuals stay in MAE/RMSE and are excluded only from MAPE; all-zero MAPE or undefined R² is unavailable, not a perfect score. Model confidence is a separate indicator. Simulation-based evaluation is not real-world forecasting accuracy. Charts may compare waste and profit descriptively, but must not claim causality or achieved waste-reduction results.

## 9. Manual reports and CSV/PDF export

The authorized user selects date/period/range, category or All, and export format. `ReportController` validates input and delegates to `ReportService`; `ReportRepo` reads permitted history; `ReportExportAdapter` converts the same report model returned to the UI. Report generation/export never mutates operational records or starts a daily process.

| Concern | CSV | PDF |
|---|---|---|
| Content | UTF-8 header and structured rows with raw numeric values | Title, filters, summary cards, tables, explanatory notes and supported charts |
| Dates | Consistent ISO dates | Human-readable bakery-local dates and generation timestamp |
| Provenance | Exact `data_origin` values; explicit simulated-record identification | Visible Simulated Data label/note wherever simulation results are included |
| Undefined percentage | Blank/null numeric cell plus Not Applicable status | Not Applicable |
| Finance | Snapshot-derived numeric values, signed where meaningful | Malaysian Ringgit formatting without changing calculations |

Use a predictable sanitized filename, for example `BakeSmart_Weekly_Report_2026-10-05_to_2026-10-11.pdf`. Paginate long PDFs and include report date/page information. Return files on demand to Android for viewing/saving/sharing; remove temporary server files after delivery where used. Include no credentials, tokens, internal model files or unpermitted user details. On error, explain the failure and preserve selected filters for manual retry.

## 10. Planned verification

| Case | Expected result |
|---|---|
| Administrator calls donation/waste/status mutation; manager calls charity administration | Rejected by Node after JWT/active-profile checks; no writes |
| No completed simulation, zero/negative quantity, quantity exceeding remaining, inactive partner, blank reason | Rejected with unchanged allocation/balance |
| Concurrent donation 7 and waste 6 against leftover 10 | At most one succeeds; invariant holds after each commit |
| Failure after allocation insert but before balance/audit update | Entire transaction rolls back |
| Status PENDING to COLLECTED to COMPLETED | Confirmed audited progress; no second allocation/subtraction; intended-recipient event |
| Cancellation before policy is defined | Unsupported mutation rejected; no automatic release or history deletion |
| Cold-start confidence null | Heuristic label only; no fabricated percentage/model reference |
| Predicted 100, units sold 80, produced 120 | Signed error -20, leftover 40; leftover and discarded waste displayed separately |
| FIFO cost fixture above; master price subsequently changes | RM11 cost retained; negative profit/margin preserved |
| Zero production, zero demand or zero revenue | Corresponding rates Not Applicable; no NaN/infinity or misleading zero |
| Detailed transactions joined to daily/allocation summaries | Revenue/cost/quantities counted once |
| Weekly/category-filtered UI, CSV and PDF | Matching totals/formulas/null handling, date filters and origin labels |
| 20 active categories and 50 rows/list; seven-day report | Module 6 performance/UI acceptance targets apply |

## 11. Planned implementation order

1. Align normalized allocation DTOs, statuses, field mappings and shared report formulas with Module 0.
2. Plan `DailyResultRepo`/allocation transaction participation, charity validation and audit before write endpoints.
3. Add manager allocation/status Services and administrator charity Services; leave cancellation policy visibly unresolved.
4. Build `ReportRepo` queries with correct aggregation grain and price/FIFO cost snapshots; build the common report model and CSV/PDF adapter.
5. Add protected Controllers and role-specific Views, confidence/null rendering, filter validation and explicit confirmations.
6. Integrate recipient notifications and request-derived pending actions; no automatic allocation or timed scheduler.
7. Execute the planned allocation, permission, reporting, export, compatibility and usability checks from [Module 6](../operation_reminders_testing/README.md). No such implementation tests are executed in this documentation task.

The unresolved donation-cancellation/reallocation policy is recorded in the [change report](../../planning_documents_change_report.md). It does not authorize an invented release rule or automatic donation workflow.
