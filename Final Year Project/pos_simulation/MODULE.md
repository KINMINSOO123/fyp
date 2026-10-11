# Module 4: POS Simulation

**Build Order:** 5th (depends on Module 0: Data Foundation, Module 1: Node.js Middleware, Module 2: ML Prediction, Module 3: Inventory + Integration)
**Status:** High-Level Plan — ready for detailed breakdown
**Architecture:** View → `PosSimulationController` → `PosSimulationService` → Repos/existing Services (see `../ARCHITECTURE.md`)

---

## 1. Goal

Build the **POS Simulation System** — generates realistic daily sales data for testing and development training. It uses the stored `DailyPrediction` as the already-contextualised baseline, adds configured time-slot/stochastic variation, and handles stock-outs without applying weather, holiday, season or other contextual multipliers a second time.

This is a **SUPPORTING** system (master doc §4.3). `DailyResult` stores detailed completed-simulation outcomes. After successful completion, one validated `DailySalesRecord` per category is created with `DataOrigin.SIMULATION_GENERATED`. Such records may support development training; evaluation using them is labelled simulation-based and never presented as real-world accuracy.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** — needs `sales_transactions`, `production_decisions`, `daily_production`, `daily_results`, `daily_sales_records`, `daily_predictions`
- **Module 1 (Node.js Middleware)** — needs `ContextService` for traceability/display, `DailyPredictionRepo`, Express/auth infrastructure and `PosSimulationController`
- **Module 2 (ML Prediction)** — indirectly: validated simulation-origin `DailySalesRecord` may be supplied by Node.js for development training
- **Module 3 (Inventory + Integration)** — needs FIFO-aware `inventoryService.deductForProduction` + `reverseProductionDeduction` (for re-simulation); also imports the **reporting-only** `ingredientCostCalculator.costPerUnit(category)` to compute `daily_results.ingredient_cost` (cost on produced units). Finance stays decoupled from the Smart Recommendation Engine.
- **`../ARCHITECTURE.md`** — defines the layered pattern this module follows

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 4.1 | Sales Transaction Repo | Repo | `sales_transactions` CRUD + findByDate + findBySlot + deleteByDate |
| 4.2 | Daily Production Repo | Repo | `daily_production` CRUD + findByDate + deleteByDate |
| 4.3 | Daily Result Repo (extended) | Repo | `daily_results` CRUD — shared with Module 3, adds write + deleteByDate methods |
| 4.4 | Sales Distribution Service | Service | Apply time-slot weights (40/35/25) from constants (pure calc) |
| 4.5 | `PosSimulationService` | Service | Core engine — stored-prediction baseline, stochastic/time-slot variation, stock-out logic |
| 4.6 | `TransactionRecordingService` | Service | FIFO deduction once before sales, atomic operational writes, simulation-origin history creation and failure reversal |
| 4.7 | `PosSimulationController` | Controller | Class-based endpoints to trigger simulation and query transactions/results |
| 4.8 | Stock-Out Notification Service | Service | Emit alerts when simulated demand exceeds production (collaborates with `PosSimulationService`; persists/audits through Node.js services) |
| 4.9 | Manual Correction Service | Service | Allows staff to correct produced/sold/demand/lost_sales and add notes after demo or real operation |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Stock-out handling | Cap sales at production + track `lost_sales` column | Matches master doc's "STOCK OUT! 18 lost sales" example; requires Module 0 schema update |
| 2 | Transaction granularity | Batched — each transaction has random qty 1-3 units | ~50-100 transactions/day per category; realistic for analytics |
| 3 | Production qty source | Saved `production_decisions.final_selected_qty`, with optional `producedOverride` for tests/demo scenarios | Realistic manager decision path while still easy to demo |
| 4 | Re-simulation | Allow with `forceRefresh` flag | Deletes existing data + restores inventory through correction FIFO batches, then re-inserts; useful for testing scenarios |
| 5 | Context handling | Retrieve for traceability/display only | The stored `DailyPrediction` already incorporates relevant contextual effects; multiplying them again would double count. |
| 6 | Historical output | Create validated `DailySalesRecord(unitsSold, SIMULATION_GENERATED)` only after success | Separates ML history from the detailed `DailyResult` and preserves provenance. |

---

## 5. Schema Update Required (Module 0)

The `lost_sales` decision requires adding columns to `daily_results`; the financial reporting layer requires additional financial columns and `sales_transactions` snapshots.

```sql
ALTER TABLE sales_transactions
  ADD COLUMN unit_price numeric NOT NULL DEFAULT 0,   -- snapshot of bread_categories.selling_price at sale moment (RM)
  ADD COLUMN subtotal   numeric NOT NULL DEFAULT 0;   -- quantity * unit_price (RM)

ALTER TABLE daily_results
  ADD COLUMN estimated_demand int,          -- units_sold + lost_sales; analysis only
  ADD COLUMN lost_sales int DEFAULT 0,
  ADD COLUMN remaining_unallocated_leftover int NOT NULL DEFAULT 0,
  ADD COLUMN notes text,                    -- optional manual correction / stock-out note
  ADD COLUMN revenue         numeric NOT NULL DEFAULT 0,  -- SUM(sales_transactions.subtotal) for this category-day
  ADD COLUMN ingredient_cost numeric NOT NULL DEFAULT 0,  -- cost of all PRODUCED units (sold + leftover)
  ADD COLUMN gross_profit    numeric NOT NULL DEFAULT 0;   -- revenue - ingredient_cost
```

**Column relationships after simulation:**
```
units_sold      ≤ produced                                  ← capped at production
leftover        = produced - units_sold                    ← always ≥ 0
estimated_demand = units_sold + lost_sales                 ← analysis only
remaining_unallocated_leftover = leftover at completion
waste_rate      = (leftover / produced) × 100
error_pct       = |predicted_units_sold - units_sold| / units_sold × 100
unit_price      = bread_categories.selling_price snapshot (captured per sale row)
subtotal        = quantity * unit_price
revenue         = SUM(sales_transactions.subtotal WHERE category+date match)
ingredient_cost = produced * costPerUnit(category)         ← cost on PRODUCED, not sold (by design)
gross_profit    = revenue - ingredient_cost
```

**Financial data is reporting-only.** `revenue`, `ingredient_cost`, `gross_profit`, `unit_price`, `subtotal` are written by this module and never read back by prediction (Module 2) or the Smart Recommendation Engine (Module 3). They power the dashboard's financial view (Module 5). `ingredient_cost` is computed on **produced** (not sold) units so wasted/donated bread's cost counts — making waste visibly eat profit.

**Per-transaction snapshot:** when the simulator inserts each `sales_transactions` row, it copies the category's current `selling_price` into `unit_price` and computes `subtotal = quantity * unit_price`. Historical sale rows therefore retain the price in force at sale time even after `bread_categories.selling_price` is updated.

---

## 6. Endpoints (handled by `PosSimulationController`; registered by thin router modules)

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/sales/simulate` | Trigger simulation `{ date, producedOverride?, forceRefresh? }` |
| GET | `/api/sales/:date` | Get all transactions for a date (all categories, all slots) |
| GET | `/api/sales/:date/summary` | Get daily_results for a date (all categories) |
| PATCH | `/api/sales/:date/summary/:categoryId` | Manual correction `{ produced?, sold?, demand?, lost_sales?, notes? }` |
| GET | `/api/sales/:date/slot/:slot` | Get transactions for a specific slot (morning/afternoon/evening) |
| GET | `/api/sales/:date/category/:categoryId` | Get transactions for a specific category on a date |

---

## 7. Simulation Flow

```
POST /api/sales/simulate { date: "2026-06-26", forceRefresh: false }
  ↓
PosSimulationService.simulateDay(date, options)
  │
  ├─ STEP 0: Handle re-simulation (if forceRefresh)
  │   ├─ Check if daily_results exist for date
  │   └─ If yes:
  │       ├─ Read existing daily_production → get produced qty per category
  │       ├─ Reverse inventory deductions (inventoryService.reverseProductionDeduction)
  │       ├─ Delete sales_transactions for date
  │       ├─ Delete daily_production for date
  │       └─ Delete daily_results for date
  │
  ├─ STEP 1: Fetch prediction for date (predictionRepo.findByDate)
  │
  ├─ STEP 2: Fetch context for traceability/display only (ContextService)
  │   → do not apply weather/holiday/season multipliers to the stored prediction again
  │
  ├─ STEP 3: Validate all confirmed quantities and required valid inventory
  ├─ STEP 4: Deduct required ingredients through FIFO exactly once
  │   → create linked inventory movements/idempotency reference
  │
  ├─ STEP 5: For each bread category:
  │   ├─ 3a. Determine production qty (production_decisions.final_selected_qty OR producedOverride for tests)
  │   ├─ 3b. Calculate simulated demand:
  │   │       estimated_demand = stored predicted_units_sold × configured stochastic variation
  │   ├─ 3c. Apply stock-out logic:
  │   │       sold = min(demand, produced)
  │   │       leftover = produced - sold
  │   │       lost_sales = max(0, demand - produced)
  │   ├─ 3c'. IF lost_sales > 0:
  │   │       → notificationService.emitStockOutAlert(categoryId, date, lost_sales)
  │   │       → log to system_logs + push event to dashboard subscribers
  │   ├─ 3d. Distribute sold across 3 time slots (40/35/25 + noise)
│   ├─ 3e. Generate transactions per slot: qty 1-3 each, random times, each row carries
│   │        unit_price = category.selling_price (snapshot) + subtotal = quantity * unit_price
│   ├─ 3f. Record daily_production row linked to production_decision_id when available
│   ├─ 3g. Record DailyResult row (with estimated_demand + lost_sales) + financial cache:
│   │        revenue         = SUM(transactions.subtotal) for this category-day
│   │        ingredient_cost = produced * ingredientCostCalculator.costPerUnit(category)
│   │        gross_profit    = revenue - ingredient_cost   (cost on PRODUCED, not sold)
│   └─ 3h. Create validated DailySalesRecord(unitsSold, SIMULATION_GENERATED, source DailyResult)
  │
  ├─ STEP 6: Commit the completed simulation atomically
  └─ ON any failure after deduction: roll back transaction or reverse linked FIFO movements;
     do not store a completed result or DailySalesRecord
```

**Manual correction rule:** When staff correct a result, recalculate `leftover`, `lost_sales`, `waste_rate_pct`, `error_units`, and `error_pct` from the corrected values, **and recompute the financial cache** `revenue`, `ingredient_cost` (on the corrected `produced`), and `gross_profit`, store `notes`, and log the correction in `system_logs`. This is for realistic demo cleanup and real-world data entry mistakes; it does not change raw `sales_transactions` (hence `revenue` is unaffected by a correction that only changes `produced`/`sold` accounting) unless a later enhancement adds transaction-level editing.

---

## 8. Stock-Out Example

```
Croissants on a rainy public holiday:
├─ stored predicted_units_sold: 110
│  (the prediction already incorporated the relevant weather/holiday context)
├─ produced: 100 (confirmed feasible production decision)
├─ stochastic variation produces estimated_demand: 118
├─ no weather/holiday multiplier is reapplied
├─ units_sold: min(118, 100) = 100
├─ leftover: 100 - 100 = 0
├─ lost_sales: 118 - 100 = 18    ← STOCK OUT
├─ waste_rate: 0%
└─ DailySalesRecord: unitsSold=100, dataOrigin=SIMULATION_GENERATED

Morning (40%):  40 croissants sold (~20 transactions, qty 1-3 each)
Afternoon (35%): 35 croissants sold (~18 transactions)
Evening (25%):  25 croissants sold (~13 transactions)
Total: 100 sold, 0 leftover, 18 lost sales
```

---

## 9. File Structure (extends Node.js `backend/src/`)

> Follows the layered architecture from `../ARCHITECTURE.md`: Model → Repo → Service → Controller.

```
backend/src/
├── repositories/
│   ├── salesTransactionRepo.ts      # NEW — sales_transactions CRUD
│   ├── dailyProductionRepo.ts       # NEW — daily_production CRUD
│   ├── dailyResultRepo.ts           # SHARED with Module 3 (detailed completed simulation)
│   └── dailySalesRecordRepo.ts      # historical units_sold + DataOrigin
├── services/
│   ├── posSimulationService.ts      # NEW — stored-prediction baseline engine
│   ├── salesDistributionService.ts  # NEW — slot weight logic (pure calc)
│   ├── transactionRecordingService.ts # NEW — writes results, deducts inventory
│   ├── notificationService.ts       # stock-out alerts (collaborates with PosSimulationService)
│   └── ... (existing services from Modules 1, 3)
├── controllers/
│   └── posSimulationController.ts   # FILLS Module 1 stub; routes remain modules
```

---

## 10. Integration Points

| Talks To | Direction | Purpose |
|---|---|---|
| Module 1 ContextService | Internal call | Fetch weather + calendar for traceability/display, not multiplier application |
| Module 1 DailyPredictionRepo | Internal call | Read the stored prediction baseline for the date |
| Module 3 productionDecisionService | Internal call | Read manager-selected production quantities when available |
| Module 3 inventoryService | Internal call | Deduct ingredients from FIFO batches after production + reverse on re-simulation |
| Module 1 systemLogRepo | Internal call | Write stock-out alert events to `system_logs` audit trail |
| Module 5 Dashboard | Push event | Real-time stock-out alert surfaced on the manager dashboard |
| Module 2 (indirect) | Via validated DTO from Node.js | `SIMULATION_GENERATED` DailySalesRecord may support development training/evaluation with explicit labelling |
| Supabase | Repo calls | Read predictions, write transactions/production/results |

---

## 11. Cross-Module Dependencies (updates needed)

| Dependency | Impact | File to Update |
|---|---|---|
| Module 0 schema | Add `estimated_demand`, `lost_sales`, `remaining_unallocated_leftover` to `daily_results`; add `daily_sales_records` with `DataOrigin`; retain financial snapshot fields | `data_foundation/README.md` + `MODULE.md` |
| Module 3 inventoryService | Add `reverseProductionDeduction` method (for re-simulation) | `inventory_integration/README.md` |
| Module 3 ingredientCostCalculator | New reporting-only service: `costPerUnit(category)` used to compute `ingredient_cost` on produced units | `inventory_integration/README.md` |

---

## 12. What This Module Does NOT Include

- ❌ Generating predictions → Module 2 (this module consumes predictions)
- ❌ Inventory constraint logic → Module 3 (this module deducts inventory after production)
- ❌ Dashboard UI → Module 5 (this module provides the data)
- ❌ Automatic scheduled simulation → out of prototype scope; Module 6 only sends reminder notifications, and the manager manually triggers `/api/sales/simulate`

---

## 13. Next Steps (Detailed Breakdown)

See `README.md` in this folder for the detailed plan (repo methods, service function signatures, controller code, verification).

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
