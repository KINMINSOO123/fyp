# Module 5: Leftover Management, Dashboard and Reports

**Design revision - 2026-10-16:** At the user's request, FEFO replaces the report's FIFO policy: eligible batches are consumed by `expiry_date ASC, received_date ASC, id ASC`. The DOCX/report mirror remain unchanged; this is an explicit departure from Sections 4.5.3-4.5.4 and 4.9.3, including BR-INV-05/FR-INV-06. Other report requirements still apply.

**Build order:** sixth, after Modules 0–4. **Status:** proposed design reconciled 2026-10-11; no completed backend, database, Flutter dashboard or verification is claimed. The latest `RSW_SooKinMin_Project1 (1).docx` controls, especially Sections 3.4–3.6, 4.5.3–4.5.4, 4.6–4.9 and Table 4.27. See the [report mirror](../../RSW_SooKinMin_Project1.docx.md) for navigation.

## 1. Scope and mapping

Technical Module 5 implements planning responsibilities for functional module 5 **Leftover, Donation and Waste Management** and functional module 6 **Reporting and Dashboard**. Its Views also present prediction, inventory, simulation and notification information from functional modules 2–4 and 7; administrator charity maintenance belongs to functional module 8. This preserves Section 1.4.2's eight functional modules and the four objectives of next-day prediction, inventory-aware recommendations, POS simulation and leftover/donation management.

The application is for one bakery on Android. Configured active categories drive filters, rows and calculations; four categories/five ingredients are seed examples, not UI or algorithm limits. Reports support the reference workload of up to 20 categories. No customer ordering/payment, delivery/marketplace, real POS hardware, multi-branch functionality or automatic background scheduling is introduced.

## 2. Components and dependencies

| Planned component | Responsibility and dependencies |
|---|---|
| `LeftoverManagementController -> LeftoverManagementService` | Read completed results; recommend an action without allocating; validate manager-confirmed donation/waste and status updates |
| `DailyResultRepo`, `DonationRepo`, `WasteRecordRepo` | Lock a result and persist its allocation/remaining balance within one transaction; category comes through DailyResult |
| `CharityPartnerController -> CharityPartnerService -> CharityPartnerRepo` | Administrator creates/updates/deactivates charity partners; retained donation links remain valid |
| `DashboardController -> DashboardService -> ReportRepo` | Role-permitted summaries and charts; no prediction, simulation or allocation on a dashboard read |
| `ReportController -> ReportService -> ReportRepo/ReportExportAdapter` | Date/period/category filtering, shared calculations and manually requested CSV/PDF exports |
| `AuditService`, `NotificationService` | Transaction-coupled allocation/status audit and intended-recipient event notification |
| `ManagerDashboardView`, `AdministratorDashboardView`, `LeftoverManagementView`, `DonationStatusView`, `CharityPartnersView`, `ReportsView` | Role-specific controls, clear pending/confirmed state, simulated labels and filter/export actions |

Module 0 supplies the canonical tables; Module 1 supplies JWT/active-profile validation, role enforcement, administration and notification boundaries. Module 2 supplies stored prediction modes, confidence and origin-labelled evaluation. Module 3 supplies jointly feasible recommendations/confirmed decisions. Module 4 supplies committed DailyResults, transaction price snapshots and FEFO batch-cost snapshots. Views request ordinary business data through Node; foreground notifications use the explicitly allowed recipient-scoped Supabase Realtime path.

## 3. Endpoints and permissions

| Endpoint | Permission and contract |
|---|---|
| `GET /api/leftovers?date=...&breadCategoryId=...` | Both roles: permitted completed-result summaries |
| `GET /api/leftovers/:resultId/recommendation` | Manager: non-persisting donation/waste suggestion |
| `POST /api/donations` | Manager: confirmed `{ dailyResultId, quantity, charityPartnerId }` |
| `POST /api/waste-records` | Manager: confirmed `{ dailyResultId, quantity, disposalReason }` |
| `PATCH /api/donations/:id/status` | Manager: explicit confirmed status change, validated transition and audit |
| `GET/POST /api/admin/charity-partners`; `PATCH /api/admin/charity-partners/:id` | Administrator: manage active partners; deactivate referenced records |
| `GET /api/dashboard` | Both roles: permitted dashboard data, date/category filters |
| `GET /api/reports`; `GET /api/reports/export` | Both roles: manual report, period/date range/category filters; `format=CSV` or `PDF` for export |

Node obtains actor and stored role from a validated JWT and active profile, not from request fields. Administrators do not inherit manager-only allocation/status actions. For manager donation forms, eligible active charities are supplied through the protected leftover View DTO; managers do not gain administrator CRUD access.

## 4. Allocation and status invariants

One completed DailyResult is the source for each allocation. A donation or waste row stores `daily_result_id`, not a redundant category; category/date are obtained through the related result. There is no `LeftoverRecord` table. Require a positive whole-number quantity and explicit manager confirmation. Donation requires an active charity at commit; waste requires a nonblank disposal reason.

Lock the result, recompute committed donations/waste, validate the proposed quantity against remaining leftovers, and atomically insert the allocation, update the remaining balance and append audit metadata. Competing allocations serialize on the same result. Any failure rolls back the allocation and balance changes. Enforce:

```text
leftover = produced - units_sold
leftover = donated + wasted + remaining_unallocated
donated >= 0; wasted >= 0; remaining_unallocated >= 0
```

The system may recommend donation or waste, but does not create either automatically. A donation begins `PENDING` and its confirmed progress uses `COLLECTED` and `COMPLETED`; `CANCELLED` is part of the report's status vocabulary. Older `RECORDED`, `PICKED_UP`, `DELIVERED` terminology maps respectively to `PENDING`, `COLLECTED`, `COMPLETED` for donation status only. Notification delivery `DELIVERED` remains a separate domain. Cancellation/reallocation rules are not specified sufficiently by the report: expose the unresolved policy in planning and do not implement a cancellation mutation or automatically release its quantity until that policy is settled.

## 5. Reporting contracts

Use one calculation path for UI, CSV and PDF:

| Indicator | Formula/interpretation |
|---|---|
| Sales prediction error | `units_sold - predicted_units_sold`; signed |
| Estimated demand | `units_sold + lost_sales`; analytical, not model target |
| Leftover rate | `leftover / produced * 100`; includes donated/unallocated leftovers |
| Discarded waste rate | `wasted / produced * 100`; only confirmed disposal counts as waste |
| Sales fulfilment | `units_sold / estimated_demand * 100` |
| Revenue | `sum(transaction.quantity * transaction.unit_price_snapshot)` |
| Ingredient cost | Sum of actual FEFO batch quantities consumed multiplied by their stored unit-cost snapshots, with unit conversion |
| Gross profit / margin | `revenue - ingredient_cost`; `(gross_profit / revenue) * 100` |

Zero-denominator percentages are **Not Applicable**, with null numeric API values; signed error and negative gross profit/margin are valid. Current ingredient master prices must not recalculate historical production cost. DailyResult totals and detailed transactions are alternative aggregation levels, not additive totals. Charts show associations without claiming that a waste/profit trend proves causal business improvement. Financial values are reporting-only direct ingredient-cost estimates, not net profit or decision inputs.

`MODEL` predictions display numerical tree-agreement confidence and Low Confidence below the configured threshold (initially 75%). `COLD_START` displays a low-confidence heuristic label with `confidence = null` and no model version; never display a fabricated score. Prediction-performance comparison uses selected validated DailySalesRecord units sold with actual → imported → simulation priority and explicit origin labels. Simulation-based metrics are not evidence of real-world accuracy.

Reports are generated manually, including seven-day/weekly reports. Date/range/category filters are shared by UI and export. CSV uses UTF-8, consistent ISO dates, raw numeric values and `data_origin`; PDF includes selected period/category, generation time, labels, tables and supported charts. Simulated records are visibly identified in UI/PDF and in CSV provenance columns.

## 6. Planned implementation and verification

1. Define normalized allocation/status DTOs and shared report formulas against the canonical schema.
2. Plan locked transactional allocation Repos, active-charity validation, manager status workflow and audit; keep cancellation policy open.
3. Build report aggregation from committed operational records, price snapshots and FEFO cost snapshots; add common CSV/PDF rendering.
4. Add protected Controllers and role-specific Views, manual confirmations, mode-aware confidence and origin labels.
5. Integrate recipient status/surplus notifications and request-derived pending indicators; introduce no timer or auto-donation path.
6. Verify concurrent allocation, zero/excess quantities, inactive charity, missing reason, wrong-role rejection, status audit, FEFO cost changes, signed/undefined reporting cases, exports and the Module 6 performance/usability targets.

See the [detailed design](README.md), [canonical schema](../../database_canonical_design.md), [test plan](../operation_reminders_testing/README.md) and [traceability](../../planning_documents_change_report.md). These are planned checks, not results.
