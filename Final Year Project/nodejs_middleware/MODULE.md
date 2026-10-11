# Module 1: Node.js Middleware and External Adapters

**Build order:** second, after Module 0. **Status:** proposed design reconciled on 2026-10-11; backend components and checks below are not implemented or verified. The latest `RSW_SooKinMin_Project1 (1).docx` is the authority; the repository [report mirror](../../RSW_SooKinMin_Project1.docx.md) supports navigation. See report Sections 3.4–3.6, 4.2, 4.5, 4.8 and 4.9.

## 1. Responsibility and functional-module mapping

This technical module provides the protected Express API, application access management, administration, contextual-service adapters and notification infrastructure for a single bakery's Android application. It supports functional modules 1 **User and Access Management**, 2 **Demand Prediction**, 3 **Inventory and Smart Production Recommendation**, 4 **POS and Sales Simulation**, 5 **Leftover, Donation and Waste Management**, 6 **Reporting and Dashboard**, 7 **Alerts and Notifications**, and 8 **System Administration**. Technical modules 0–6 are build packages, not a replacement for the eight functional modules in report Section 1.4.2.

Flutter business requests follow `View -> Controller -> Service -> Repo/Adapter`. Router modules register routes and are not UML Controller classes. Node owns application-table CRUD and supplies validated DTOs through `FastApiMlClient` to thin FastAPI routes and Python ML Services. FastAPI has no Supabase database client or credentials. Report Sections 4.2.4 and 4.8 explicitly permit Flutter to use Supabase Authentication, recipient-scoped Supabase Realtime for foreground notification events, and FCM for background notifications.

## 2. Planned components

| Boundary | Planned responsibility |
|---|---|
| Authentication middleware; `UserProfileRepo` | Verify JWT signature, issuer, audience and expiry; load active profile before permission checks |
| `ProfileController` / `ProfileService` / `UserProfileRepo` | Own-profile reads and permitted edits; `AuthAdminAdapter` coordinates provider-managed identity changes |
| `UserAdministrationController` / `UserAdministrationService` / `UserProfileRepo` / `AuthAdminAdapter` | Administrator account creation, role/status changes and final-active-administrator protection |
| `SettingsController` / `SettingsService` / `BakerySettingsRepo` / `SystemSettingsRepo` | Singleton bakery settings, allowlisted typed parameters and nonsecret external-service configuration |
| `AuditController` / `AuditService` / `SystemLogRepo` | Append-only audit records and administrator-filtered read access |
| `WeatherService`, `CalendarService`, `ContextService`; `WeatherRepo`, `CalendarRepo`; `OpenWeatherMapClient`, `NagerDateClient` | Cached, validated date context with identified fallback and retry; calendar traceability through `prediction_calendar_events` |
| `PredictionOrchestrationService` / `FastApiMlClient` | Validated units-sold history and context to Python; validated predictions persisted by Node |
| `ModelManagementService` / `FastApiMlClient` | Separate candidate training, evaluation, explicit activation and restoration |
| `NotificationController` / `NotificationService` | Recipient authorization, per-type preferences, notification persistence and eligible push attempts |
| `NotificationRepo`, `NotificationPreferenceRepo`, `FcmTokenRepo`, `NotificationDeliveryRepo`, `FcmPushAdapter` | Recipient read state, recipient-owned active tokens and delivery-attempt history |
| `PendingActionController` / `PendingActionService` | Read current pending actions on app open/refresh; no timer or operational execution |

## 3. Permissions and endpoints

Every protected endpoint requires a valid JWT and `user_profiles.account_status = ACTIVE`. Exactly one stored role is `BAKERY_MANAGER` or `SYSTEM_ADMINISTRATOR`. Email and client actor/role fields never establish authority. Table 4.27 does not grant administrators manager-only actions.

| Endpoint | Permission and responsibility |
|---|---|
| `GET/PATCH /api/profile` | Both roles; authenticated user's permitted profile fields only |
| `GET/POST /api/admin/users`; `PATCH /api/admin/users/:id` | Administrator; create accounts or change permitted profile/role/status fields; preserve final active administrator |
| `GET/PATCH /api/admin/settings`; `GET /api/admin/service-status` | Administrator; validated settings and nonsecret connectivity status |
| `GET /api/admin/audit` | Administrator; filters by date, event, user and outcome; no log edit/delete |
| `GET /api/notifications`; `PATCH /api/notifications/:id/read` | Both roles; own recipient rows only |
| `GET/PATCH /api/notification-preferences`; `POST/DELETE /api/fcm-tokens` | Both roles; own type preferences and device registration/deactivation |
| `GET /api/pending-actions` | Both roles; derived pending state restricted to permitted actions |
| `POST /api/predictions`; `GET /api/recommendations/:date`; `PUT /api/production-decisions`; `POST /api/simulations` | Manager only; Modules 2–4 provide business rules |
| `POST /api/admin/models/train`; `POST /api/admin/models/:id/evaluate`, `/activate`, `/restore` | Administrator only; no automatic activation |
| `POST /api/donations`; `POST /api/waste-records`; `PATCH /api/donations/:id/status` | Manager only; Module 5 validates allocation/status |
| `/api/admin/charity-partners` and permitted item routes | Administrator manages charities; referenced records are deactivated |
| `GET /api/dashboard`, `/api/reports`, `/api/reports/export`, `/api/leftovers` | Both roles; authorized read-only operational summaries and reports |

Inventory/category/recipe/batch management belongs to the administrator. Manager Views expose operational actions; administrator Views expose account, catalogue, settings, charity, model and audit actions. Both roles have profile, permitted reports/dashboard and personal notification Views.

## 4. Cross-module contracts

- `DailySalesRecord.unitsSold` is the training and comparable evaluation target. `estimatedDemand = unitsSold + lostSales` is analytical. Select one validated category/day observation in `ACTUAL_TRANSACTION -> IMPORTED_HISTORICAL -> SIMULATION_GENERATED` priority before counting the 30 distinct days.
- MODEL predictions require at least 30 distinct validated daily observations and a valid active model. They have a model-version reference and numerical confidence. `ConfidenceService` calculates `100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))`; `predicted_units_sold = max(0, round(mu))`. Confidence below the configurable threshold, initially 75%, is Low Confidence; it measures tree agreement, not accuracy probability.
- COLD_START predictions have `modelVersionId = null`, `confidence = null` and a low-confidence heuristic label. Use the mean available valid units sold as `Bc`, otherwise the category's configured base; predict `max(0, round(Bc * Dt * Mt * Wt * Ht))`.
- Recommendations reserve outstanding confirmed decisions against a temporary balance, then allocate unconfirmed categories in ascending `display_order`. Each recommendation is `min(predicted_units_sold, max_producible)` and reduces remaining shared balances. Revising a decision replaces its old quantity; processed decisions are excluded. Confirmation changes no inventory.
- Official simulation requires the selected date's stored prediction and manager-confirmed decision. One Node-owned transaction/RPC revalidates combined availability, locks rows, deducts valid batches in `received_date, id` order, and commits inventory, movements, production, transactions, result and one validated simulation-origin observation together. Failure rolls back everything; uniqueness and locks prevent duplicate deduction. Stored contextual effects are not applied again.
- Model candidates and active models are compared on the same chronologically later untouched test dataset. Reject activation if candidate MAE is higher; preserve the active model on failures. RF/LR share training/test data; report MAE, RMSE, MAPE and R² with undefined values unavailable, not perfect.

## 5. Notification and platform contracts

`notifications.recipient_user_id` identifies one intended active user. Preferences use `(user_id, notification_type)`; tokens must be valid, active and owned by that recipient. Notification deduplication and read state are per recipient. Events include low stock, expiry, low confidence, lost sales, surplus, donation-status changes and external/system failures.

Foreground Flutter receives relevant notification events through Supabase Realtime. The narrowly scoped authenticated application-table SELECT exception permits a user to read their own notification rows while their profile is active. This is not general table CRUD; all writes, including mark-read, use Node. No Node polling/SSE/WebSocket relay replaces the selected Realtime design.

Push is submitted only after preference and token checks and after the in-app record commits. `notification_deliveries` tracks `PENDING`, `SUBMITTED`, `DELIVERED`, `FAILED`, `SKIPPED`. Provider acceptance is `SUBMITTED`; `DELIVERED` needs delivery evidence. Failure preserves the in-app record. No active daily timed reminders or background scheduling are planned.

## 6. Build order and planned verification

1. Adopt Module 0's current schema and discriminated DTOs; establish error handling and server-only configuration.
2. Plan JWT/profile authorization, own-profile edits, user administration and atomic final-administrator protection before business endpoints.
3. Add settings and audit boundaries, then contextual adapters and validated ML contracts.
4. Add recipient notification Repos, Node read/write APIs, scoped Realtime policy and eligible FCM delivery handling.
5. Connect Modules 2–5 controllers, transaction-owning Repos and pending-state queries; expose corresponding role-specific Views.
6. Verify unauthorized/inactive requests, cross-role rejection, forged actor fields, concurrent final-admin changes, settings validation, null cold-start confidence, recipient isolation, opt-in push and delivery-state transitions. Use [Module 6's planned checks](../operation_reminders_testing/README.md); none have been executed as part of this documentation change.

See the [detailed plan](README.md), [architecture](../ARCHITECTURE.md), [canonical schema](../../database_canonical_design.md) and [traceability/change report](../../planning_documents_change_report.md).
