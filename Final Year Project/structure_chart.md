# Smart Bakery Food Waste Reduction System - Structure Chart

**View:** Functional decomposition (user-facing capabilities)
**Scope:** Single bakery
**Status:** Refined - aligns with `ARCHITECTURE.md` and module plans (Modules 0-6)
**Last Updated:** July 2026

---

## Legend

| Marker | Meaning |
|---|---|
| `[CORE]` | The system's central pillar - everything else supports this |
| `*` | Signature feature / viva highlight |
| `(Supabase-managed)` | Handled by a platform service, not custom-built |
| `(new)` | Branch added during refinement |

---

## Structure Chart

```text
Smart Bakery Food Waste Reduction System
|
|-- User & Access Management                         [Supabase Auth]
|   |-- Authentication (login/logout, JWT)
|   |-- Profile Management
|   `-- Access Control (authenticated RLS)           (Supabase-managed)
|
|-- Demand Prediction (CORE)                         [Module 2: Python ML Server]
|   |-- Validated Daily Sales History
|   |   |-- Actual Transactions
|   |   |-- Imported Historical Records
|   |   `-- Simulation-Generated Records (development use; labelled evaluation)
|   |-- Feature Engineering
|   |   |-- Historical (rolling avg, trends, same-weekday avg)
|   |   |-- Temporal (day-of-week, month, monsoon season)
|   |   `-- External (weather, holidays/events)
|   |-- ML Prediction (Random Forest + Linear Regression baseline)
|   |-- Manager-Initiated Prediction Generation
|   |-- Confidence Calculation (tree variance)
|   |-- Cold-Start Fallback (<30 days heuristic)
|   |-- Administrator-Initiated Candidate Training
|   |-- Chronological Holdout Evaluation (MAE, RMSE, MAPE, R^2)
|   |   `-- Origin Label (real/imported/simulation-based/mixed)
|   |-- Feature Importance & Explainability
|   `-- Model Version Management
|       |-- Administrator Activation
|       `-- Restore Previous Valid Version
|
|-- Inventory & Smart Recommendation                 [Module 3: Node.js]
|   |-- Ingredient Management
|   |-- Bread Category Management
|   |-- Recipe Management
|   |-- FIFO Inventory Transactions (deduct oldest batch, restock batch, log)
|   |-- Low-Stock Alerts
|   |-- Inventory Quality Checks (expiry, snapshot mismatch, missing recipe rows)
|   |-- Constraint Checking
|   |-- Operational Feasibility (inventory levels, max_producible)
|   |-- Production Decision Capture (manager follows/reduces/overrides)
|   `-- Smart Recommendation Engine *                (prediction + inventory -> adjusted qty + options)
|       |-- Apply ML demand prediction
|       |-- Check recipe + FIFO inventory constraints
|       |-- Generate production options
|       `-- Save manager decision
|
|-- POS Simulation                                   [Module 4: Node.js]
|   |-- Production Decision Consumption (uses manager-selected qty when available)
|   |-- Manager-Initiated Simulation Run
|   |-- Stored DailyPrediction Baseline (context not multiplied twice)
|   |-- FIFO Deduction Exactly Once + Failure Reversal
|   |-- Sales Transaction Recording
|   |-- Financial Snapshotting (unit_price, revenue, ingredient_cost, gross_profit cache)
|   |-- End-of-Day DailyResult Aggregation
|   `-- DailySalesRecord Creation (SIMULATION_GENERATED)
|
|-- Leftover, Donation & Waste                       [Module 5: Node.js]
|   |-- Remaining Unallocated Leftover Tracking
|   |-- Charity Partner Management
|   |-- Action Recommendation (no automatic allocation)
|   |-- Manager-Confirmed Donation
|   |-- Manager-Confirmed Waste + Disposal Reason
|   `-- Allocation/Waste Rate Tracking
|
|-- External Data Integration                        (new) [Module 1: Node.js adapters]
|   |-- Weather API Adapter (OpenWeatherMap)
|   `-- Calendar/Holiday API Adapter (Nager.Date / Google Calendar)
|
|-- Financial Reporting                              (cross-cutting: reporting only)
|   |-- Ingredient Cost Calculator   [Module 3]
|   |-- Financial Snapshotting       [Module 4]
|   `-- Financial Summary Service   [Module 5]
|
|-- Reporting & Dashboard                            [Module 5: Flutter + Node.js]
|   |-- Prediction View (accuracy, confidence, feature importance)
|   |-- Manager Action Buttons (generate prediction, run POS simulation)
|   |-- Inventory View (stock, low-stock, expiring FIFO batches, quality status)
|   |-- Sales View (timeslot distribution, trends)
|   |-- Waste & Donation View (waste rate, donation impact)
|   |-- Financial View (revenue, ingredient cost, gross profit; waste-vs-profit chart)
|   |-- Weekly Summary Report
|   `-- PDF / CSV Export
|
|-- Alerts & Notifications                           (new) [Module 1 infra + cross-module emitters]
|   |-- Prediction Reminder Notification  [Module 6: reminder service]
|   |-- Simulation Reminder Notification  [Module 6: reminder service]
|   |-- Ingredient Low-Stock Alert         [Module 3: inventoryService]
|   |-- Low-Confidence Prediction Alert    [Module 2/1: after manager-generated prediction]
|   |-- Bread Stock-Out Alert              [Module 4: PosSimulationService]
|   |-- Donation Status Notification       [Module 5: LeftoverManagementService]
|   |-- Notification Delivery
|   |   |-- Node API/SSE/WebSocket relay (foreground bell badge)
|   |   `-- Node FCM adapter (background push)
|   `-- Notification Center (bell icon + list + mark-read)
|
|-- Operation Reminders & Testing                    (new) [Module 6: reminder + test plan]
|   |-- Predefined Reminder Time Settings
|   |-- Reminder Emission Audit
|   |-- Manual Prediction Flow Test
|   |-- Manual Simulation Flow Test
|   `-- End-to-End Manager Daily Cycle Test
|
`-- System Administration                            [Module 1: Node.js]
    |-- User & Access Management
    |-- Bakery Settings (name, hours, location type)
    |-- Configurable Prediction/Cold-Start/Confidence Constants
    |-- Model Candidate Evaluation, Activation & Restoration
    |-- System Logs / Audit Trail
    |-- Notifications & Device Tokens (FCM)
    `-- Backup & Restore                             (Supabase-managed)
```

---

## Faults Fixed vs. Original Chart

| # | Fault in original | Fix |
|---|---|---|
| 1 | "Production Recommendation" placed under Demand Prediction | Moved into Inventory branch as **Smart Recommendation Engine**. The ML server only outputs raw predictions; constraint-aware recommendation is Module 3. |
| 2 | Feature Collection listed only Weather/Calendar/Temporal | Expanded ML features to Historical, Temporal, and External; moved operational constraints to Module 3. |
| 3 | Background scheduling over-scoped the prototype | Replaced with **Operation Reminders & Testing**. The system reminds the manager at predefined times, but prediction and simulation remain manager-initiated. |
| 4 | Reporting & Analytics vs Dashboard duplicated the same domains | Merged into a single **Reporting & Dashboard** branch. |
| 5 | "Product Management" misnamed | Renamed to **Bread Category Management** because the schema uses `bread_categories`. |
| 6 | Missing ML sub-features | Added confidence, cold-start fallback, evaluation, feature importance, versioning, and manual/admin retraining. |
| 7 | Missing External Data Integration as a distinct concern | Added **External Data Integration** for Weather/Calendar adapters in Node.js. |
| 8 | Missing System Logs/Audit | Added under System Administration. |
| 9 | Role Management & Backup & Restore over-scoped for FYP | Kept but de-emphasized: Access Control = Supabase Auth/RLS; Backup = Supabase-managed. |
| 10 | Notifications were spread across modules but absent from chart | Added **Alerts & Notifications** branch with reminder/alert types emitted by Modules 2/3/4/5/6 and delivery handled by Module 1. |

---

## Notes on Scope Decisions

- **Operation Reminders replace the old scheduler idea** - the prototype sends `prediction_reminder` and `simulation_reminder` notifications at predefined times, but the manager still presses the dashboard buttons to generate predictions and run POS simulation. Full background automation can be stated as a future production enhancement.
- **Functional decomposition retained** - this view suits the viva overview. Implementation tracking stays in `ARCHITECTURE.md`.
- **Alerts & Notifications is cross-module** - delivery infrastructure lives in Module 1; reminder/alert types are emitted by Modules 2 (`low_confidence`), 3 (`low_stock`), 4 (`stock_out`), 5 (eligible donation-status events), and 6 (`prediction_reminder`, `simulation_reminder`).
- **Financial Reporting is cross-cutting and read-only** - Module 3 calculates ingredient cost, Module 4 writes financial snapshot/cache values, and Module 5 aggregates them for dashboard/reporting. Financial values must not drive ML prediction or smart recommendation decisions.
- **Manager decision remains auditable** - `production_decisions` records whether the manager followed, reduced, or overrode the recommendation before POS simulation consumes the selected quantity.
- **Model lifecycle is administrator-controlled** - retraining creates candidates; chronological evaluation precedes explicit activation, and a previous valid version can be restored.
- **Simulation data is provenance-labelled** - each successful category result creates a validated `DailySalesRecord` marked `SIMULATION_GENERATED`; simulation-based evaluation is never presented as real-world accuracy.
- **Surplus allocation is manager-controlled** - the system recommends donation or waste, but records neither until the Bakery Manager confirms it.

---

**Document Status:** Refined and finalized. Conforms to `ARCHITECTURE.md` and the module plans (Modules 0-6).
