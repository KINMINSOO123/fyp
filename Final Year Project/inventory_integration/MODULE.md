# Module 3: Inventory + Integration

**Build Order:** 4th (depends on Module 0: Data Foundation, Module 1: Node.js Middleware, Module 2: ML Prediction)
**Status:** High-Level Plan — ready for detailed breakdown
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

---

## 1. Goal

Build the inventory management system + the **smart recommendation engine** that combines Module 2's predictions with inventory constraints to produce the "yeast shortage" scenario from §4.5 — the system's signature intelligent behavior.

This module extends the Node.js middleware — it fills in the `inventoryController.ts` stub from Module 1 and adds new business logic files. No new server.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** — needs tables: `inventory`, `inventory_batches`, `inventory_log`, `recipes`, `ingredients`, `bread_categories`, `production_decisions`, `daily_production`, `daily_results`, `donations`, `system_logs`
- **Module 1 (Node.js Middleware)** — needs the Express app skeleton, auth middleware, Supabase client, route aggregator
- **Module 2 (ML Prediction)** — calls `/predict` endpoint to get base predictions before applying constraints

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 3.1 | Inventory/Recipe Repos | Repo | Supabase CRUD for inventory, inventory_batches, inventory_log, recipes, ingredients tables |
| 3.2 | Ingredient Calculator | Service | Compute ingredient requirements for a production qty (pure calc) |
| 3.3 | Constraint Checker | Service | Detect insufficient ingredients vs requirements (pure calc) |
| 3.4 | Inventory Service | Service | Auto-deduct, FIFO restock, low-stock/expiry alerts (calls repos). On low-stock detection, calls `notificationService.emit({ type: 'low_stock', severity: 'warning', ... })` (Module 1) so staff receive background push via FCM |
| 3.4a | FIFO Batch Service | Service | Consume oldest non-expired batches first; expire/discard batches; keep inventory snapshot totals synchronized |
| 3.4b | Inventory Quality Service | Service | Detect expired active batches, snapshot/batch mismatches, negative quantities, and missing recipe ingredients |
| 3.5 | Recipe Service | Service | Recipe business logic (calls recipeRepo) |
| 3.6 | Production Decision Service | Service | Confirm manager's final production quantity, enforce feasibility/reason rules, and audit the decision without deducting inventory |
| 3.7 | Smart Recommendation Engine | Service | Reads stored `DailyPrediction` through `DailyPredictionRepo`, applies recipe/inventory feasibility and produces options; never calls FastAPI directly |
| 3.8 | Weekly Summary Service | Service | Aggregated waste/trend per category (calls repos) |
| 3.9 | Ingredient Cost Calculator **(reporting-only)** | Service | `costPerUnit(categoryId)` = Σ(recipe grams_per_unit × ingredient cost per gram). Pure calc, calls `recipeService` + `ingredientRepo`. **Never imported by `recommendationEngine` or `constraintChecker`** — core project philosophy: finance does not drive optimisation. Used only by Module 4 (`daily_results.ingredient_cost` cache) and Module 5 (dashboard). |
| 3.10 | Controllers | Controller | Class-based inventory, recipe, recommendation and summary request handlers; thin Express routers remain modules |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Inventory updates | Auto-deduct on production + manual restock | Matches master doc's "data collection for ML" goal; baker also manually records restocks |
| 2 | Constraint handling | Show both options (produce reduced + order more) | Matches master doc §4.5 exactly — baker decides |
| 3 | Recipe management | DB-driven (recipes table), editable via dashboard | Changes take effect instantly without app update; matches §9 "centralized business logic" |
| 4 | Low-stock alerts | Dashboard badge + morning report + system_logs + notification emission (Module 1's `NotificationService`) | Node persists the alert through `NotificationRepo`, exposes foreground changes through its authenticated API/SSE/WebSocket boundary, and sends background alerts through the FCM adapter. Flutter and FastAPI do not access Supabase tables directly. |
| 5 | FIFO inventory | Lightweight ingredient batch tracking | Restock creates expiring batches; production consumes oldest usable batch first. This is realistic for perishable bakery ingredients without making inventory the main project. |
| 6 | Manager production decisions | Confirm selected option before baking | Captures when the manager accepts, reduces, or overrides the recommendation; stores manager/time/reason, remains auditable, and becomes the quantity source for POS Simulation. Inventory is not deducted at confirmation time. |
| 7 | Inventory quality checks | Service-level warnings, not a separate module | Keeps the MVP realistic by detecting bad inventory data before recommendations depend on it. |
| 8 | Financial data in optimisation | **Strictly forbidden.** `recommendationEngine` and `constraintChecker` only read inventory in grams + predicted demand in units. | Core project philosophy. The new `ingredientCostCalculator` (3.9) is a **reporting-only** service — never imported into the recommendation path. Prices/costs are exposed to Module 4 reporting only. This is auditable: `rg "selling_price\|unit_cost\|ingredientCost" src/services/recommendationEngine.ts src/services/constraintChecker.ts` should yield zero hits. |
| 9 | Prediction dependency | Use the stored `DailyPrediction`; if absent, return a validation error | Only `PredictionOrchestrationService` may call `FastApiMlClient`, preserving Service → Adapter and preventing duplicate prediction generation. |

---

## 5. New Endpoints (extend Module 1's Node.js routes)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/inventory` | List all inventory with ingredient names + low-stock flags |
| GET | `/api/inventory/batches` | List FIFO batches, filter by ingredient/status/expiry |
| POST | `/api/inventory/restock` | Record manual restock (creates FIFO batch + updates snapshot + logs) |
| POST | `/api/inventory/deduct` | Deduct for production using FIFO batches (auto, called by production flow) |
| GET | `/api/inventory/log` | Inventory change history (filterable by reason/date) |
| GET | `/api/inventory/low-stock` | List ingredients below reorder_threshold |
| GET | `/api/inventory/expiring-soon` | List active batches expiring within N days |
| GET | `/api/inventory/quality` | Inventory data-quality report |
| POST | `/api/inventory/batches/:batchId/discard` | Mark an expired/spoiled batch as discarded and reduce snapshot |
| GET | `/api/recipes` | All recipes (all categories × all ingredients) |
| GET | `/api/recipes/:categoryId` | Recipe for one category (ingredient grams per unit) |
| PUT | `/api/recipes/:categoryId` | Update recipe (editable from dashboard) |
| GET | `/api/recommendation/:date` | **THE SMART RECOMMENDATION** (prediction + inventory integration) |
| POST | `/api/production-decisions` | Confirm manager-selected production quantity/option before POS simulation |
| GET | `/api/summary/weekly` | Weekly summary per category (produced, sold, waste, trend) |

---

## 5.1 Use Case: Confirm Production Decision

The Bakery Manager reviews the generated production recommendation and confirms the final quantity of each bread category to be produced. The Manager may accept, reduce, or override the recommended quantity, subject to the calculated production-feasibility constraints.

Preconditions:
- The Bakery Manager is logged in.
- A production recommendation exists for the selected production date.
- Required recipes and current/as-of inventory information are available.
- `max_producible` has been calculated for each applicable bread category.

Postconditions:
- The confirmed decision is stored in `production_decisions` with production date, bread category, predicted demand, recommended quantity, `max_producible`, final quantity, decision type, reason, confirmation time, and Manager ID.
- A reason is required and stored when the Manager reduces or overrides the recommendation.
- The confirmed decision becomes available to POS Simulation through `production_decisions.final_selected_qty`.
- A `production_decision_confirmed` audit record is written to `system_logs`.
- Ingredient inventory is not deducted merely by confirming the production decision.

---

## 6. The Signature Feature — Smart Recommendation

`GET /api/recommendation/:date` (master doc §4.5)

```
1. Call Module 2's /predict for target date
   → predictions: [{ Croissants: 120, confidence: 88% }, ...]

2. For each category, calculate ingredient requirements:
   ├─ Croissants: 120 units
   │   ├─ Flour:  120 × 80g = 9,600g  (9.6 kg)
   │   ├─ Butter: 120 × 15g = 1,800g  (1.8 kg)
   │   ├─ Sugar:  120 × 5g  = 600g
   │   ├─ Yeast:  120 × 2g  = 240g  ❌
   │   └─ Salt:   120 × 1g  = 120g
   │
3. Check against inventory for the target date:
   ├─ Flour:  30,000g ✓ (need 9,600g)
   ├─ Butter: 4,000g  ✓ (need 1,800g)
   ├─ Yeast:  200g    ❌ (need 240g) → CONSTRAINT!
   └─ ...

   Note: for today/future recommendations, `inventory` is the aggregate snapshot.
   For historical as-of reruns, stock is reconstructed from `inventory_log`
   where `effective_date <= target_date`. The underlying stock is stored in
   `inventory_batches`; if production is confirmed, Module 3 deducts from the
   oldest usable batch first.

4. For constrained categories, compute:
   ├─ max_producible = min across ingredients (have / grams_per_unit)
   │   └─ Yeast: 200g / 2g = 100 units → max = 100
   │
   └─ Build options:
       ├─ Option 1: Produce 100 (constrained) — may miss 20 sales
       └─ Option 2: Order 40g+ yeast tonight → produce 120 ✅ (recommended)

5. Return full smart recommendation:
   {
     date, categories: [{
       category_name: "Croissants",
      predicted_units_sold: 120,
       confidence: 88,
       recommended_production: 100,  // adjusted
       ingredient_requirements: [...],
       constraints: [{ ingredient: "Yeast", have: 200, need: 240, shortfall: 40 }],
       options: [
         { id: 1, action: "produce_reduced", qty: 100, note: "May miss 20 sales" },
         { id: 2, action: "order_ingredients", order: [{Yeast: 40g}], produce: 120, recommended: true }
       ]
     }]
   }
```

---

## 7. File Structure (extends Module 1's `backend/src/`)

> Follows the layered architecture from `../ARCHITECTURE.md`: View → Controller class → Service → Repo. Services call Repos, not Supabase; Express routers remain thin modules.

```
backend/src/
├── repositories/                   # NEW — Repo layer (Supabase only)
│   ├── inventoryRepo.ts            # inventory snapshot CRUD + findLowStock
│   ├── inventoryBatchRepo.ts       # FIFO batch CRUD + findUsableByIngredient + findExpiringSoon
│   ├── inventoryLogRepo.ts         # inventory_log table
│   ├── productionDecisionRepo.ts   # production_decisions table
│   ├── recipeRepo.ts               # recipes table CRUD
│   ├── ingredientRepo.ts           # ingredients table
│   ├── dailyResultRepo.ts          # daily_results (for weekly summary)
│   ├── donationRepo.ts             # donations (for weekly summary)
│   ├── breadCategoryRepo.ts        # bread_categories
│   └── predictionRepo.ts           # daily_predictions (reads cached predictions)
├── services/                       # NEW — Service layer (business logic, calls repos)
│   ├── ingredientCalculator.ts     # Compute requirements from recipes (pure calc)
│   ├── constraintChecker.ts        # Detect insufficient ingredients (pure calc)
│   ├── fifoBatchService.ts         # FIFO deduction, expiry/discard handling
│   ├── inventoryQualityService.ts  # Inventory consistency + expiry data checks
│   ├── productionDecisionService.ts # Manager selected option / override persistence
│   ├── recommendationEngine.ts     # THE signature feature (calls repos + ML server)
│   ├── inventoryService.ts         # Auto-deduct, restock, low-stock (calls repos)
│   ├── recipeService.ts            # Recipe business logic (calls recipeRepo)
│   ├── weeklySummaryService.ts     # Aggregated waste/trend per category (calls repos)
│   └── ingredientCostCalculator.ts # REPORTING-ONLY — cost per produced unit (never imported by recommendationEngine/constraintChecker)
├── controllers/                    # Controller layer (thin HTTP handlers)
│   ├── inventoryController.ts     # FILLS Module 1 stub (calls inventoryService)
│   ├── recipeController.ts        # NEW (calls recipeService)
│   ├── recommendationController.ts # NEW (calls recommendationEngine)
│   └── summaryController.ts       # NEW (calls weeklySummaryService)
└── ... (rest from Module 1)
```

---

## 8. Integration Points

| Talks To | Direction | Purpose |
|---|---|---|
| Module 2 (ML Server) | Outgoing HTTP | Calls `/predict` to get base predictions |
| Supabase (inventory, inventory_batches, production_decisions, recipes, ingredients) | Outgoing | Read inventory + FIFO batches + recipes, write decisions + inventory_log |
| Flutter Dashboard | Incoming | Receives smart recommendation for display |
| Module 4 (POS) | Incoming (later) | POS calls `/inventory/deduct` when production recorded |
| Module 6 (Operation Reminders + Testing) | Incoming (later) | Reminder tests may verify low-stock notifications and weekly summary visibility |
| Module 1 `notificationService` | Outgoing (internal call) | Emits `low_stock` alert when `inventory.quantity_grams < ingredients.reorder_threshold` |

---

## 8.1 Low-Stock Notification Flow

```
inventoryService.detectLowStock() / inventoryService.deductForProduction()
  ↓
1. inventoryRepo.findLowStock()                          ← Repo (Supabase)
   → [ { ingredient_id, name, quantity_grams, reorder_threshold, ... }, ... ]
2. For each ingredient below threshold:
   ├─ Call Module 1's notificationService.emit({
   │     type: 'low_stock',
   │     severity: 'warning',
   │     title: `Low Stock: ${ingredient.name}`,
   │     message: `Only ${ingredient.quantity_grams}g remaining (reorder threshold ${ingredient.reorder_threshold}g)`,
   │     relatedId: ingredient.ingredient_id
   │   })
   │   ├─ Dedupe guard (in notificationService): skip if unread 'low_stock' with
   │   │   same related_id (ingredient_id) already exists
    │   ├─ Otherwise: NotificationRepo inserts notification
    │   ├─ Node authenticated API/SSE/WebSocket relay → Flutter foreground bell badge
    │   └─ FcmPushAdapter.broadcast → FCM → staff phone lock-screen trays (even app closed)
   └─ Continue to next ingredient
3. RETURN summary { lowStockIngredients, alertsEmitted }
```

This means low-stock is no longer just discoverable via the dashboard badge — staff are **proactively notified on their phones** even when the app is in the background, so they can reorder ingredients before the morning bake.

---

## 9. What This Module Does NOT Include

- ❌ Generating predictions → Module 2 (this module consumes them)
- ❌ POS simulation / sales recording → Module 4
- ❌ Dashboard UI rendering → Module 5 (this module provides the data)
- ❌ Scheduled nightly workflow automation → out of prototype scope; Module 6 sends reminders and tests the manager-controlled flow

---

## 10. Next Steps (Detailed Breakdown)

See `README.md` in this folder for the detailed plan (function signatures, service logic, route handlers, request/response flow, verification).

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
