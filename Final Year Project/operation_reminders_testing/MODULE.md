# Module 6: Manual Operation Indicators and Testing

**Build order:** seventh, integrating Modules 0–5. **Status:** proposed workflow and test plan, reconciled 2026-10-11 with the latest `RSW_SooKinMin_Project1 (1).docx`, Sections 1.4, 3.4–3.6, 4.2, 4.5, 4.8–4.10. No test results, completed implementation or UAT outcomes are claimed. See the [report mirror](../../RSW_SooKinMin_Project1.docx.md) for navigation.

## 1. Scope and functional mapping

This technical package integrates functional module 7 **Alerts and Notifications** and verifies all eight functional modules: User and Access Management; Demand Prediction; Inventory and Smart Production Recommendation; POS and Sales Simulation; Leftover, Donation and Waste Management; Reporting and Dashboard; Alerts and Notifications; System Administration. Technical modules 0–6 are a build sequence; they do not replace the report's eight functional modules.

The four objectives remain next-day prediction, inventory-aware recommendations, POS simulation, and leftover/donation management. One bakery uses an Android application. There is no automatic background scheduling. Four bread categories/five ingredients are seed examples; verification includes configured active categories up to the report's reference workload of 20.

## 2. Manual workflow and pending state

1. On opening or refreshing the application, `GET /api/pending-actions` derives current state through `PendingActionController -> PendingActionService -> DailyPredictionRepo/ProductionDecisionRepo/DailyResultRepo` and allocation Repos where needed.
2. A Bakery Manager explicitly generates the next-day prediction, reviews the shared-ingredient recommendation and confirms a feasible production decision. Confirmation changes no inventory.
3. For the selected simulation date, defaulting to the current date, the manager explicitly starts official simulation only after a matching stored prediction and confirmed decision exist.
4. One Node-owned PostgreSQL transaction/RPC locks/revalidates shared inventory, deducts FIFO exactly once and commits all simulation records together; failure rolls back all changes.
5. The manager reviews resulting leftovers and explicitly confirms each donation or waste allocation/status update.
6. A System Administrator separately initiates candidate training, evaluation, explicit activation or restoration; administrator accounts do not inherit manager actions.

`PendingActionService` returns missing/ready/completed prerequisites and permitted actions. It cannot call prediction, training, confirmation, simulation or allocation methods. Reads on app open/refresh replace the old timed-reminder plan. Daily 06:00/18:00 reminders are not current scope; timed reminders may be future work and still must not execute operations.

## 3. Event notifications

`NotificationService` identifies authorized active recipients for low stock, expiry, low confidence, lost sales, excessive surplus, donation-status and external/system-failure events. Notification rows use `recipient_user_id`, per-type preferences and recipient-owned valid active FCM tokens. Read state and deduplication are per recipient.

Flutter uses Supabase Authentication, recipient-only Supabase Realtime notification events in the foreground and FCM for background delivery. The authenticated notification SELECT policy is a narrow explicit exception; ordinary application-table CRUD and all notification writes/mark-read requests use Node. Delivery records retain `PENDING`, `SUBMITTED`, `DELIVERED`, `FAILED`, `SKIPPED`; provider acceptance is not confirmed delivery. Neither Realtime nor FCM creates a background scheduler.

## 4. Measurable NFR reference environment

Use Android 10+, at least 4 GB RAM, stable network at least 10 Mbps and an available backend. Data contains up to 20 active categories, 365 daily records/category and at most 50 displayed records/list page. These are test conditions, not permanent category or history limits.

| Requirement | Planned acceptance measurement |
|---|---|
| NFR-PER-01 | At least 95% of requests for login, dashboard, prediction-history, inventory-list, report-list and notification-list screens complete within 3 seconds |
| NFR-PER-02 | Next-day prediction or recommendation for the reference workload completes within 15 seconds |
| NFR-PER-03 | A 12-hour simulation or seven-day report for up to 20 categories completes within 30 seconds |
| NFR-USA-03 / NFR-COM-01 | Android 10+ and viewport checks from 360×640 to 412×915 dp; no overlapping/clipped controls or required horizontal scrolling for primary functions |
| NFR-USA-04 | At least 80% of UAT participants independently complete login, prediction, production confirmation, simulation and leftover recording, without moderator assistance or task-blocking usability problems |

Record measured timings, device/network/dataset conditions and actual UAT participation only when tests are performed. No participant count or successful result is invented here.

## 5. Required verification coverage

| Area | Planned checks |
|---|---|
| Access/administration | Valid JWT then active stored profile; cross-role rejection both ways; final active administrator preserved under concurrency; own profile cannot edit role; settings validation and immutable audit |
| Prediction/history | Exact DataOrigin values; one validated category/day actual → imported → simulation; threshold at 29/30 distinct days; no active model means heuristic; cold-start null confidence/model reference |
| Confidence/evaluation | Defined tree-agreement boundaries; strict below-75% Low Confidence; chronological untouched holdout; shared RF/LR data; MAE/RMSE/MAPE/R² null semantics; higher-MAE activation rejected |
| Recommendations/FIFO | Shared ingredient commitments, replacing revisions, excluding processed decisions, display-order allocation, no buffer; receipt order versus expiry order and same-date ID tie-break |
| Simulation | Required stored prediction/manager confirmation; no double-context multipliers; duplicate requests deduct once; locked joint stock; rollback after each mutation point; exact movement costs |
| Leftovers/reports | Concurrent allocation, positive quantities, active charity/reason, unresolved cancellation blocked; signed error, real discarded waste, negative profit, Not Applicable denominators; CSV/PDF/UI parity |
| Notifications | Recipient isolation through Node and Realtime; read/dedup per user; type opt-in and token ownership; delivery state evidence; push failure retains in-app record |
| Manual workflow | Open/refresh derives indicators without operations; time passage alone triggers nothing; manager/admin action separation |

## 6. Planned implementation/verification order

1. Adopt the current report traceability and Module 0 schema/DTO contracts; prepare deterministic fixtures and reference performance data.
2. Plan access, administration, provenance and pure calculation checks alongside their modules.
3. Add transaction/concurrency/failure-injection verification for shared ingredients, simulation and allocations.
4. Integrate request-derived pending indicators and event notification delivery/isolation.
5. Run end-to-end manual role workflows, export parity, NFR performance, Android layout/compatibility and independent UAT when implementation exists.
6. Record actual evidence and unresolved defects without rewriting plans as completed results.

See the [detailed test plan](README.md) and [traceability/change report](../../planning_documents_change_report.md). This reconciliation edits Markdown only; no tests, package installation, migration or deployment are requested or performed.
