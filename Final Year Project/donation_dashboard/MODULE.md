# Module 5: Donation + Dashboard

**Build Order:** 6th (depends on Module 0: Data Foundation, Module 1: Node.js Middleware, Module 2: ML Prediction, Module 3: Inventory + Integration, Module 4: POS Simulation)
**Status:** High-Level Plan — ready for detailed breakdown
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

---

## 1. Goal

Build the **Leftover Donation System** + the **Bakery Manager Dashboard** (Flutter mobile app + backend aggregation endpoints).

This module spans two layers:
1. **Backend (Node.js)** — donation endpoints + dashboard data aggregation endpoints
2. **Frontend (Flutter)** — the actual View layer (screens, widgets, charts)

Leftover management recommends donation or waste for unavoidable surplus, but the Bakery Manager confirms and records every allocation. It maintains category-specific remaining unallocated leftovers. The dashboard provides daily and analytical Views plus weekly reports with supported PDF/CSV export.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** — needs `donations`, `waste_records`, `charity_partners`, `daily_results`, `daily_predictions`, model/evaluation, inventory and sales tables through Node.js Repos
- **Module 1 (Node.js Middleware)** — needs Express/auth infrastructure, TypeScript Repos, `LeftoverManagementController` and `DashboardController`
- **Module 2 (ML Prediction)** — dashboard evening/prediction views fetch ML metrics (MAPE, R², feature importance) via Node.js proxy to ML server
- **Module 3 (Inventory + Integration)** — dashboard morning view calls `recommendationEngine.generateRecommendation`; inventory view reuses `inventoryService`; waste view reuses `weeklySummaryService`
- **Module 4 (POS Simulation)** — donation service reads `daily_results.leftover` (produced - sold) from simulation output; dashboard midday/sales views read `sales_transactions`
- **`../ARCHITECTURE.md`** — defines the layered pattern this module follows

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 5.1 | Charity Partner Repo | Repo | `charity_partners` CRUD |
| 5.2 | Donation Repo | Repo | `donations` CRUD + findByDate + weekly summary (write methods; read was in Module 3) |
| 5.3 | `LeftoverManagementService` | Service | Recommend an action; record only manager-confirmed donation/waste; enforce allocation and update remaining unallocated leftover |
| 5.3a | Waste Repo | Repo | `waste_records` CRUD by category/date/result |
| 5.4 | Dashboard Service | Service | Aggregates data for each view (morning/midday/evening + inventory/sales/waste/prediction) |
| 5.4a | Financial Summary Service **(reporting-only)** | Service | Aggregates `daily_results.revenue` / `ingredient_cost` / `gross_profit` for daily/weekly/monthly/lifetime + the waste-vs-profit correlation series. Reads only the cached daily financial columns + sales_transactions. Never calls the recommendation engine or influences prediction. |
| 5.5 | Donation Controller | Controller | Charity partner CRUD + donation endpoints (fills Module 1 stub) |
| 5.6 | Dashboard Controller | Controller | Combined endpoints per view (fills Module 1 stub) |
| 5.7 | Flutter App | View | Complete mobile dashboard — all views + reusable widgets |
| 5.8 | Report Service + Export Adapter | Service/Adapter | Generate weekly report and render supported PDF/CSV exports |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Leftover action trigger | Bakery Manager confirmation | The system recommends but never automatically creates a donation or waste record |
| 2 | Allocation | Category-specific donation/waste, possibly repeated while leftovers remain | Donation plus waste must not exceed leftover; remaining unallocated quantity is maintained |
| 3 | Flutter scope | All views | 3 daily views + inventory + sales + waste/donation + prediction + weekly summary |
| 4 | Dashboard endpoints | Combined per view | One endpoint aggregates all data for that view; fewer HTTP round trips |
| 5 | Financial reporting | **Reporting-only.** New `financialSummaryService` aggregates cached `daily_results.revenue/ingredient_cost/gross_profit` and `sales_transactions.subtotal` for display. Never calls `recommendationEngine`, never influences prediction. | Core project philosophy: finance proves the business value of waste reduction (dual-axis waste↔profit chart) but never drives optimisation. Gross profit uses cost of PRODUCED (not sold) so wasted/donated bread's cost counts. |
| 6 | Weekly export | `ReportService` with `ReportExportAdapter` for PDF/CSV | Keeps report aggregation in the Service layer and format rendering behind an adapter |

---

## 5. Leftover, Donation and Waste Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/charity-partners` | List charity partners |
| POST | `/api/charity-partners` | Add charity partner |
| PUT | `/api/charity-partners/:id` | Update charity partner |
| POST | `/api/donations` | Record a manual donation `{ date, charity_partner_id, items: [{category_id, qty}] }` |
| POST | `/api/leftovers/recommend` | Return a non-persisting recommended action |
| POST | `/api/waste-records` | Record manager-confirmed category waste with disposal reason |
| GET | `/api/donations/:date` | Get donations for a date |
| GET | `/api/donations/summary` | Weekly donation summary `?weekStart=` |

---

## 6. Dashboard Endpoints (fills Module 1 `dashboardController.ts` stub)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/dashboard/morning` | Morning view: prediction + recommendation + production decision action + ingredient checklist + low-stock |
| GET | `/api/dashboard/midday` | Midday view: live sales tracking (predicted vs sold so far) |
| GET | `/api/dashboard/evening` | Evening view: daily results + accuracy + donations + per-category ML model status **+ today's Revenue / Ingredient Cost / Gross Profit cards (RM)** |
| GET | `/api/dashboard/prediction` | Prediction analytics: actual-vs-predicted chart, accuracy over time, confidence/stability, feature importance |
| GET | `/api/dashboard/inventory` | Inventory view: stock levels, low-stock, expiring FIFO batches, inventory quality, usage |
| GET | `/api/dashboard/sales` | Sales view: timeslot distribution, trends `?date=` **+ Daily/Weekly/Monthly/Lifetime revenue cards (RM) + revenue-trend line + revenue-by-category breakdown + "Best-selling category" pill** |
| GET | `/api/dashboard/waste` | Waste & donation view: waste rate, donation impact `?weekStart=` **+ dual-axis chart of `waste_rate_pct` vs `gross_profit` over time (proves less waste → better profit)** |
| GET | `/api/dashboard/financial` | **(new)** Financial summary: Revenue / Ingredient Cost / Gross Profit for today / week / month / lifetime. Reporting-only — pure aggregates from `daily_results` cache. |
| GET | `/api/reports/weekly` | Generate weekly production/sales/prediction/inventory/lost-sales/leftover/donation/waste/financial report |
| GET | `/api/reports/weekly/export?format=pdf|csv` | Export the supported weekly report through `ReportExportAdapter` |

---

## 7. Manager-Confirmed Leftover Allocation Flow

```
POST /api/leftovers/recommend { date, category_id }
  ↓
LeftoverManagementService.recommendAction(...)
  ├─ Read DailyResult.leftover and remainingUnallocatedLeftover
  └─ Return recommendation only; write nothing

Bakery Manager chooses donation or waste and confirms:
  ├─ Validate quantity > 0
  ├─ Validate donated + wasted + requested ≤ leftover
  ├─ For donation: require active charity and category; insert Donation
  ├─ For waste: require category and disposalReason; insert WasteRecord
  ├─ Update remainingUnallocatedLeftover transactionally
  ├─ Write audit log
  └─ If a donation reaches its configured completion status, emit notification:
  │   notificationService.emit({
  │     type: 'donation_completed',
  │     severity: 'info',            ← info: FCM data-message (app handles, no auto lock-screen popup)
  │     title: 'Donation Completed',
  │     message: `${total_leftover} items donated to ${charity.name} on ${date}`,
  │     relatedId: donation.id
  │   })
  │   ├─ writes through NotificationRepo → Node.js foreground-notification boundary
  │   └─ pushService.broadcast → FCM data message → app handles quietly (no popup)
  └─ Return updated category allocation:
      { leftover, donated, wasted, remaining_unallocated }
```

The system never automatically creates a donation or waste record.

---

## 8. Dashboard View Data Shapes

### 8.1 Morning View (`GET /api/dashboard/morning`)
```json
{
  "date": "2026-06-26",
  "weather": { "condition": "sunny", "temp_high_c": 32 },
  "holidays": [{ "event_name": "Independence Day", "demand_multiplier": 1.30 }],
  "categories": [{
    "category_name": "Croissants",
    "predicted_units_sold": 120,
    "confidence": 88,
    "recommended_production": 115,
    "ingredient_requirements": [{ "ingredient": "Flour", "need": 9600, "have": 30000, "sufficient": true }],
    "constraints": [],
    "options": []
  }],
  "low_stock_alerts": [{ "ingredient": "Yeast", "current": 200, "threshold": 500 }],
  "all_supplies_ready": true
}
```
*Wraps `recommendationEngine.generateRecommendation` + low-stock + weather/holiday context*

### 8.2 Midday View (`GET /api/dashboard/midday`)
```json
{
  "date": "2026-06-26",
  "current_time": "13:00",
  "categories": [{
    "category_name": "Croissants",
    "predicted": 120,
    "sold_so_far": 78,
    "remaining": 42,
    "percent_sold": 65,
    "status": "on_track"
  }],
  "overall_status": "on_track"
}
```
*Reads sales_transactions so far today + daily_predictions*

### 8.3 Evening View (`GET /api/dashboard/evening`)
```json
{
  "date": "2026-06-26",
  "categories": [{
    "category_name": "Croissants",
    "predicted": 120,
    "produced": 120,
    "sold": 115,
    "leftover": 5,
    "demand": 118,
    "lost_sales": 0,
    "waste_rate_pct": 4.2,
    "accuracy_pct": 95.8,
    "revenue": 402.50,           "ingredient_cost": 108.00,   "gross_profit": 294.50
  }],
  "total_produced": 268,
  "total_sold": 250,
  "total_leftover": 18,
  "total_waste_rate": 6.7,
  "total_revenue": 875.00,         "total_ingredient_cost": 315.00,   "total_gross_profit": 560.00,
  "donation": {
    "charity": "City Food Bank",
    "quantity": 18,
    "status": "recorded"
  },
  "ml_models": [{ "category_name": "Croissants", "version": 5, "mape": 8.2, "r_squared": 0.89, "last_trained": "2026-06-26T23:00:00Z", "accuracy_trend": "improving" }]
}
```
*Reads daily_results + donations + ml_model_versions. Financial fields cached on daily_results by Module 4.*

### 8.4 Financial View (`GET /api/dashboard/financial?period=today|week|month|lifetime&date=`)

```json
{
  "period": "week",
  "date_range": { "from": "2026-06-20", "to": "2026-06-26" },
  "totals": {
    "revenue": 6125.00,
    "ingredient_cost": 2205.00,
    "gross_profit": 3920.00
  },
  "by_category": [
    { "category_name": "Croissants",  "revenue": 2450.00, "ingredient_cost": 756.00, "gross_profit": 1694.00 },
    { "category_name": "Sweet Bread", "revenue": 1960.00, "ingredient_cost": 735.00, "gross_profit": 1225.00 },
    { "category_name": "Loaves",      "revenue": 1100.00, "ingredient_cost": 392.00, "gross_profit": 708.00 },
    { "category_name": "Ciabatta",    "revenue": 615.00,  "ingredient_cost": 322.00, "gross_profit": 293.00 }
  ],
  "correlation_chart": [
    { "date": "2026-06-20", "waste_rate_pct": 12.4, "gross_profit": 540.00 },
    { "date": "2026-06-21", "waste_rate_pct":  9.1, "gross_profit": 620.00 },
    { "date": "2026-06-22", "waste_rate_pct":  7.5, "gross_profit": 690.00 }
  ]
}
```
*Reads cached `daily_results.revenue/ingredient_cost/gross_profit` — no per-sale recompute. `correlation_chart` pairs each day's `waste_rate_pct` with `gross_profit` so the Flutter dual-axis line chart shows waste falling as profit rises.*

---

## 9. File Structure

### Backend (extends Node.js `backend/src/`)

```
backend/src/
├── repositories/
│   ├── charityPartnerRepo.ts      # NEW
│   ├── donationRepo.ts            # NEW (write methods; read was in Module 3)
│   └── wasteRepo.ts               # NEW
├── services/
│   ├── leftoverManagementService.ts # NEW
│   ├── dashboardService.ts        # NEW
│   └── reportService.ts           # weekly report aggregation
├── adapters/
│   └── reportExportAdapter.ts     # PDF/CSV rendering
├── controllers/
│   ├── leftoverManagementController.ts
│   └── dashboardController.ts     # FILLS Module 1 stub
```

### Frontend (Flutter app — `flutter_app/`)

```
flutter_app/
├── lib/
│   ├── main.dart                  # Entry point
│   ├── app.dart                   # MaterialApp + routing
│   ├── models/                    # From Module 0 (Dart data classes)
│   ├── services/
│   │   ├── api_client.dart        # HTTP client to Node.js
│   │   ├── auth_service.dart      # Supabase Auth
│   │   ├── api_endpoints.dart     # URL constants
│   │   ├── fcm_service.dart       # FCM token register/refresh/unregister + background message handler
│   │   └── notification_service.dart  # Node.js REST/SSE/WebSocket boundary; no direct PostgreSQL subscription
│   ├── views/
│   │   ├── login_view.dart
│   │   ├── home_view.dart         # Bottom nav shell (morning/midday/evening tabs) + notification bell icon in app bar
│   │   ├── morning_view.dart      # Today's prediction, plan, and manager decision
│   │   ├── midday_view.dart       # Real-time sales tracking
│   │   ├── evening_view.dart      # End of day summary
│   │   ├── inventory_view.dart    # Stock levels + low-stock + expiring batches + quality
│   │   ├── sales_view.dart        # Timeslot distribution + trends + RM revenue cards/trend/by-category
│   │   ├── waste_view.dart        # Waste rate + donation impact + dual-axis waste-vs-profit chart
│   │   ├── prediction_view.dart   # Accuracy, confidence, feature importance
│   │   ├── financial_summary_view.dart  # (new) Revenue/Cost/Gross Profit cards + correlation chart
│   │   ├── weekly_summary_view.dart
│   │   └── notifications_view.dart # Alert list (unread first, then by created_at desc) + mark read + mark all read
│   ├── widgets/
│   │   ├── prediction_card.dart
│   │   ├── inventory_checklist.dart
│   │   ├── sales_tracking_table.dart
│   │   ├── daily_results_card.dart
│   │   ├── waste_chart.dart
│   │   ├── donation_card.dart
│   │   ├── low_stock_badge.dart
│   │   ├── constraint_warning.dart
│   │   ├── status_indicator.dart
│   │   ├── financial_card.dart          # (new) Revenue/Ingredient Cost/Gross Profit card
│   │   ├── waste_profit_correlation_chart.dart  # (new) fl_chart dual-axis line chart
│   │   └── notification_bell.dart # Bell icon with unread count badge
│   └── theme/
│       └── app_theme.dart
├── pubspec.yaml
└── README.md
```

---

## 10. Flutter Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.5.0       # Authentication/session only; no PostgreSQL table access
  dio: ^5.4.0                     # HTTP client for Node.js API
  fl_chart: ^0.68.0               # Charts (waste rate, sales trends, accuracy)
  intl: ^0.19.0                   # Date formatting
  provider: ^6.1.0                # State management (simple)
  go_router: ^14.0.0              # Routing
  firebase_messaging: ^15.0.0     # FCM background push notifications
  firebase_core: ^3.0.0           # Required by firebase_messaging
```

> Run `flutterfire configure` once after setup to generate `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`. See Firebase Console → Project Settings → Add App.

---

## 11. Flutter Views Overview

### Home View — Bottom navigation shell
- 3 tabs: Morning / Midday / Evening
- Drawer menu: Inventory / Sales / Waste & Donation / Prediction / Weekly Summary

### Morning View — `GET /api/dashboard/morning`
- Weather + holiday banner at top
- Per-category prediction cards (predicted demand, confidence, recommended production)
- Ingredient checklist with ✓/⚠️ per ingredient
- Constraint warnings (if any) with the 2 options (produce reduced + order more)
- Low-stock alerts section
- "All supplies ready" status indicator

### Midday View — `GET /api/dashboard/midday`
- Current time display
- Per-category table: predicted | sold so far | remaining | % sold
- Color-coded status: green (on track), yellow (behind), red (stock-out risk)
- Overall status indicator

### Evening View — `GET /api/dashboard/evening`
- Per-category results card: predicted | produced | sold | leftover | waste % | accuracy %
- Total summary (produced, sold, leftover, waste rate)
- **3 financial cards (RM): Revenue / Ingredient Cost / Gross Profit (today)** — sourced from cached `daily_results`; visibly lower gross profit on high-waste days
- Donation card (charity name, quantity, status)
- ML model status per category (version, last retrain time, MAPE, R², trend)
- "Manage leftovers" action opens manager-confirmed donation/waste forms

### Inventory View — `GET /api/inventory`
- Per-ingredient stock levels with progress bars
- Low-stock badges (red)
- Expiring-soon FIFO batches
- Inventory quality status (`ok`, `warning`, `critical`)
- Restock button (opens form to add quantity + expiry date)
- Inventory log (recent changes)

### Sales View — `GET /api/dashboard/sales?date=`
- Date picker
- Timeslot distribution chart (morning/afternoon/evening pie or bar chart)
- Per-category sales breakdown
- Transaction list (scrollable)
- **4 revenue cards (RM): Daily / Weekly / Monthly / Lifetime sales revenue**
- **Revenue-by-category breakdown (RM)**
- **Revenue trend line chart (RM over time) — replaces the unit-only trend**
- **"Best-selling bread category" pill** (category with highest units sold in period)

### Waste & Donation View — `GET /api/dashboard/waste?weekStart=`
- Weekly waste rate trend chart (fl_chart line chart)
- Per-category waste breakdown
- Donation impact summary (total donated, meals provided, charity partners)
- Weekly donation breakdown per charity
- **Dual-axis line chart: `waste_rate_pct` (left axis) vs `gross_profit` (right axis) over the same day range.** As waste falls, profit visibly rises — the visual proof of the project thesis.

### Financial Summary View — `GET /api/dashboard/financial?period=&date=` (drawer)
- Period selector: Today / Week / Month / Lifetime
- 3 headline cards: Revenue / Ingredient Cost / Gross Profit (RM)
- Per-category financial breakdown
- The dual-axis waste-vs-profit correlation chart (same as Waste view) for the selected period
- **Note for the viva:** this view is reporting-only — finance never drives production or ingredient choices (see `structure_chart.md` "Financial Reporting" branch)

### Prediction View — `GET /api/dashboard/prediction`
- Actual-vs-predicted chart per category
- Accuracy over time (line chart: MAPE per model version/category)
- Confidence/stability display (current model's avg score)
- Feature importance ranking (bar chart from feature_importance)
- Model version history table

### Weekly Summary View — `GET /api/summary/weekly?weekStart=`
- Week selector
- Per-category summary (produced, sold, leftover, donated, waste rate, trend)
- Overall totals
- Trend indicators (improving/stable/worsening)

### Notifications View — `GET /api/notifications` (foreground) + FCM background push

This view shows the unified alert stream (6 types: low_stock, low_confidence, stock_out, prediction_reminder, simulation_reminder, donation_completed).

**Foreground live updates:**
- On app launch, `notification_service.dart` uses the authenticated Node.js notification API; the final transport may be polling, SSE or a Node.js WebSocket relay.
- Flutter never subscribes directly to PostgreSQL changes.

**Background push (FCM):**
- `fcm_service.dart` initializes Firebase at app start (`FirebaseMessaging.instance.requestPermission()`, `getToken()`)
- On token received → `POST /api/fcm/register { token, device_info }` (so server knows this device)
- `onTokenRefresh` listener → re-register (Firebase rotates tokens periodically)
- `FirebaseMessaging.onBackgroundMessage` handler → silent handler that updates local notification count (data-style messages, info severity only)
- Warning/critical severity → FCM `notification` payload, auto-displays in system tray
- On logout → `DELETE /api/fcm/unregister { token }` so former staff stop receiving alerts

**Bell icon + unread badge:**
- `notification_bell.dart` widget in `home_view.dart` app bar
- Shows unread count (from `/api/notifications?unread_only=true` on launch, then incremented by Realtime + decremented on tap)
- Tap → opens `notifications_view.dart`

**Notifications list:**
- Sorted unread-first, then by `created_at DESC`
- Each row: severity icon (info / warning / critical), title, message, relative time
- Tap row → `POST /api/notifications/:id/read` → mark read, row fades to grey
- "Mark all as read" action → `POST /api/notifications/read-all`

---

## 12. Integration Points

| Talks To | Direction | Purpose |
|---|---|---|
| Module 3 `recommendationEngine` | Internal call | Dashboard morning view calls this for smart recommendation |
| Module 3 `inventoryService` | Internal call | Dashboard inventory view reuses this |
| Module 3 `weeklySummaryService` | Internal call | Dashboard waste view reuses this |
| Module 4 `DailyResultRepo` | Internal call | Leftover service reads detailed result and remaining allocation |
| Module 4 `salesTransactionRepo` | Internal call | Dashboard midday/sales views read transactions |
| Module 2 ML server (via Node.js) | HTTP proxy | Dashboard evening/prediction views fetch ML metrics |
| Module 1 `NotificationService` | Outgoing (internal call) | Leftover service emits eligible status notifications after manager-confirmed actions |
| Node.js notification boundary | Incoming (Flutter) | Authenticated polling/SSE/WebSocket foreground updates; Node owns PostgreSQL access |
| Firebase Cloud Messaging | Incoming (Flutter) | FCM background push — staff phones receive alerts even when app is closed (warning/critical = lock-screen tray popup; info = silent data message) |
| Flutter ↔ Node.js | HTTP | Flutter calls Node.js dashboard/donation/notification endpoints |

---

## 13. What This Module Does NOT Include

- ❌ Generating predictions → Module 2 (dashboard displays them)
- ❌ Inventory constraint logic → Module 3 (dashboard morning view calls recommendationEngine)
- ❌ POS simulation → Module 4 (donation reads simulation output)
- ❌ Automatic donation or waste creation; the system only recommends and the Bakery Manager confirms

---

## 14. Next Steps (Detailed Breakdown)

See `README.md` in this folder for the detailed plan (repo methods, service function signatures, controller code, Flutter view examples, verification).

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
