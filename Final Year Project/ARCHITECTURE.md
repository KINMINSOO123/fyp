# System Architecture: Layered Pattern

**Applies to:** Node.js/Express application layers, the TypeScript-to-FastAPI boundary, and Python ML service layers
**Status:** Authoritative — all module plans conform to this document

> **Revised boundary:** Node.js/Express is the sole owner of Supabase PostgreSQL access and uses TypeScript `Repo` classes for it. FastAPI has no Supabase client or database repositories. TypeScript supplies validated `DailySalesRecord` and contextual DTOs through `FastApiMlClient`; thin FastAPI route modules delegate to Python service classes and return prediction, candidate-training and origin-labelled evaluation results.

---

## 1. Why Layered Architecture?

This project is a Final Year Project (FYP) defended in a viva. Examiners look for:

- ✅ **Separation of concerns** — each layer has one job
- ✅ **Testability** — services can be unit-tested by mocking repos
- ✅ **Maintainability** — change DB access without touching business logic
- ✅ **Swap-ability** — replace Supabase with another DB by only changing repos
- ✅ **Clear data flow** — easy to trace a request from UI to DB and back

---

## 2. The 5 Layers

```
┌─────────────────────────────────────────────┐
│  VIEW (Flutter)                              │  UI widgets, charts, forms
│  Talks to: Controller (via HTTP)             │  No DB, no business logic
└──────────────────┬──────────────────────────┘
                   │ HTTP REST (JSON)
┌──────────────────▼──────────────────────────┐
│  CONTROLLER (controllers/)                   │  Thin HTTP handlers
│  Talks to: Service                           │  Validates input, calls service, formats response
│  No DB, no business logic                    │
└──────────────────┬──────────────────────────┘
                   │ function calls
┌──────────────────▼──────────────────────────┐
│  SERVICE (services/)                         │  Business logic
│  Talks to: Repository                        │  Rules, calculations, orchestration
│  No direct Supabase calls                    │
└──────────────────┬──────────────────────────┘
                   │ function calls
┌──────────────────▼──────────────────────────┐
│  REPOSITORY (repositories/)                  │  Data access only
│  Talks to: Supabase (PostgreSQL)             │  find, findOne, insert, update, delete
│  No business logic, no validation            │
└──────────────────┬──────────────────────────┘
                   │ SQL via Supabase client
┌──────────────────▼──────────────────────────┐
│  DATABASE (Supabase / PostgreSQL)            │  Tables, RLS, triggers, views
└─────────────────────────────────────────────┘

MODEL (shared/types.ts | models.py | lib/models/)
  ↕ Used by ALL layers (pure data shapes, no logic)
```

---

## 3. Layer Rules (STRICT)

| Rule | Description |
|---|---|
| 1. View → Controller only | Flutter sends HTTP requests to Node.js. Never touches DB. |
| 2. Controller → Service only | Controllers call services. No direct Supabase, no repos. |
| 3. Service → Repository or external adapter | TypeScript Services call Repos for persistence and adapters for external systems. No direct Supabase or raw external HTTP calls. |
| 4. Repository → Supabase only | Repos do CRUD. No business logic, no validation. |
| 5. Model = pure shapes | Zod/Pydantic/Dart classes define data structure. No logic, no deps. |
| 6. No skipping layers | Service never calls Controller. Repo never calls Service. |
| 7. Finance is reporting-only | ML prediction and recommendation services must not read selling price, unit cost, revenue, gross profit, or finance summary services. |
| 8. Node owns PostgreSQL | Only TypeScript Repos access Supabase PostgreSQL. Flutter and FastAPI never query its tables directly. |
| 9. Thin route modules | Express router files and FastAPI route functions register/dispatch endpoints; they are modules, not UML classes and contain no business/data logic. |
| 10. ML boundary | TypeScript Service → `FastApiMlClient` → FastAPI route → Python Service. FastAPI returns results; TypeScript persists relevant records. |

---

## 4. Layer Conventions

### 4.1 Model Layer

| Service | Location | Tech |
|---|---|---|
| Node.js | `backend/shared/types.ts` | Zod schemas → inferred TS types |
| Python | `ml_server/src/models.py` | Pydantic BaseModel |
| Flutter | `flutter_app/lib/models/*.dart` | Dart data classes (json_serializable) |

**Rules:**
- Pure data shapes, no logic
- Used by all layers for type safety
- Single source of truth for what each entity looks like

### 4.2 Repository Layer

| Service | Location |
|---|---|
| Node.js | `backend/src/repositories/` |

**Naming:** `{domainName}Repo.ts`; every concrete Repo extends or follows `BaseRepo<T>`.
Examples: `inventoryBatchRepo.ts`, `dailySalesRecordRepo.ts`, `dailyPredictionRepo.ts`.

FastAPI has no repository layer because it does not own the application database. `ModelArtifactStore` is a Python artifact-persistence component, not a Supabase Repo.

**Standard methods (all repos):**
```typescript
findAll(filters?)      // SELECT * with optional filters
findOne(id)            // SELECT * WHERE id = ?
findBy(criteria)       // SELECT * WHERE column = value
insert(data)           // INSERT
update(id, data)       // UPDATE WHERE id = ?
delete(id)             // DELETE WHERE id = ?
```

**Table-specific query methods** (when needed):
```typescript
// inventoryRepo.ts
findLowStock()                              // WHERE quantity < reorder_threshold

// inventoryBatchRepo.ts
findUsableByIngredient(ingredientId, date)  // Active, non-expired batches ordered FIFO
findExpiringSoon(untilDate)                 // Expiry/FEFO alert query

// dailyPredictionRepo.ts
findByDate(targetDate)                      // WHERE target_date = ?
upsertMany(predictions)                     // INSERT ... ON CONFLICT UPDATE
```

**Rules:**
- ONLY Supabase calls (no business logic, no validation)
- Returns plain objects matching Model types
- No try/catch on business rules (let errors bubble up)
- One file per DB table

### 4.3 Service Layer

| Service | Location |
|---|---|
| Node.js | `backend/src/services/` |
| Python | `ml_server/src/services/` |

**Naming:** `{feature}Service.ts` / `{feature}Service.py`
Examples: `recommendationEngine.ts`, `inventoryService.ts`, `predictService.py`

**Rules:**
- Pure business logic (rules, calculations, orchestration)
- Calls one or more repos (never Supabase directly)
- Throws `ApiError` (Node.js) / `HTTPException` (Python) on business rule violations
- May call other services (e.g., recommendationEngine calls inventoryService)
- Calls external systems through adapters. Prediction/model services use `FastApiMlClient`; context services use weather/calendar clients.
- Financial services are reporting-only. `recommendationEngine.ts`, `constraintChecker.ts`, and the Python ML server must stay decoupled from `ingredientCostCalculator.ts`, `financialSummaryService.ts`, prices, costs, revenue, and profit fields.

### 4.4 Controller Layer

| Service | Location |
|---|---|
| Node.js | `backend/src/controllers/` |
| Python | `ml_server/src/routes/` (thin module-level FastAPI route functions) |

**Naming:** TypeScript request handlers are `{Feature}Controller` classes. Python route files are modules, not Controller classes.

**Rules:**
- Thin handlers: validate input (Zod/Pydantic) → call service → format response
- No business logic, no DB calls
- Error handling via centralized middleware (errors bubble up)

### 4.5 View Layer

| Service | Location |
|---|---|
| Flutter | `flutter_app/lib/` |

**Rules:**
- Widgets, screens, charts, forms
- Calls Node.js Controller via HTTP (never DB, never Python directly)
- Uses Model classes for type safety

---

## 5. Request Flow Example

**Scenario:** Flutter requests smart recommendation for tomorrow

```
1. Flutter (View)
   GET /api/recommendation/2026-06-27
   Authorization: Bearer <jwt>
       ↓
2. Node.js auth middleware
   Verifies JWT → attaches user to request
       ↓
3. RecommendationController (Controller class)
   Calls: recommendationEngine.generateRecommendation('2026-06-27')
       ↓
4. recommendationEngine.ts (Service)
   ├─ Calls dailyPredictionRepo.findByDate('2026-06-27')
   │   → DailyPredictionRepo (Repo) → Supabase → returns the stored prediction
   │   (If absent, return a validation error; prediction generation is owned by PredictionOrchestrationService.)
   │
   ├─ Calls inventoryRepo.findAll()
   │   → inventoryRepo (Repo) → Supabase → returns inventory snapshot totals
   │
   ├─ Calls recipeRepo.findByCategory(categoryId)
   │   → recipeRepo (Repo) → Supabase → returns recipes
   │
   ├─ Applies constraint logic (Service — pure calculation)
   │   → max_producible = min(have / grams_per_unit)
   │   → builds options (produce_reduced + order_ingredients)
   │
   └─ Returns FullRecommendation object
       ↓
5. RecommendationController (Controller class)
   res.json(recommendation)
       ↓
6. Flutter (View)
   Renders recommendation cards + constraint warnings + options
```

---

## 6. File Structure Mapping

### Node.js Middleware
```
backend/src/
├── repositories/              # Repo layer — Supabase only
│   ├── baseRepo.ts
│   ├── bakerySettingsRepo.ts
│   ├── breadCategoryRepo.ts
│   ├── ingredientRepo.ts
│   ├── recipeRepo.ts
│   ├── inventoryRepo.ts
│   ├── inventoryBatchRepo.ts
│   ├── inventoryLogRepo.ts
│   ├── productionDecisionRepo.ts
│   ├── weatherRepo.ts
│   ├── calendarRepo.ts
│   ├── dailyPredictionRepo.ts
│   ├── dailySalesRecordRepo.ts
│   ├── dailyResultRepo.ts
│   ├── donationRepo.ts
│   ├── wasteRepo.ts
│   ├── charityPartnerRepo.ts
│   ├── modelVersionRepo.ts
│   ├── featureImportanceRepo.ts
│   ├── modelEvaluationRepo.ts
│   └── systemLogRepo.ts
├── services/                  # Service layer — business logic
│   ├── contextService.ts
│   ├── weatherService.ts
│   ├── calendarService.ts
│   ├── inventoryService.ts
│   ├── fifoBatchService.ts
│   ├── inventoryQualityService.ts
│   ├── productionDecisionService.ts
│   ├── predictionOrchestrationService.ts
│   ├── modelManagementService.ts
│   ├── recipeService.ts
│   ├── ingredientCostCalculator.ts  # reporting-only, never called by recommendationEngine
│   ├── recommendationEngine.ts
│   └── weeklySummaryService.ts
├── controllers/               # Controller classes — called by Express router modules
├── routes/                    # Thin Express route-registration modules
├── adapters/                  # External clients called by Services, never Repos
│   ├── fastApiMlClient.ts
│   ├── openWeatherMapClient.ts
│   ├── nagerDateClient.ts
│   └── reportExportAdapter.ts
├── middleware/
├── config/
├── utils/
└── ...
```

### Python ML Server
```
ml_server/src/
├── routes/                    # Thin FastAPI endpoint modules
│   ├── prediction_routes.py
│   ├── training_routes.py
│   └── evaluation_routes.py
├── services/                  # Python service classes; no database access
│   ├── prediction_service.py
│   ├── feature_preparation_service.py
│   ├── model_training_service.py
│   ├── model_evaluation_service.py
│   ├── confidence_service.py
│   └── cold_start_service.py
├── models/                    # Pydantic boundary DTOs + CategoryPredictor wrapper
├── infrastructure/
│   └── model_artifact_store.py
├── config/
└── ...
```

The FastAPI tree intentionally has no `repositories/` directory and no Supabase configuration.

### Flutter App
```
flutter_app/lib/
├── models/                    # Model layer — Dart data classes
├── views/                     # View layer — screens, widgets
├── controllers/               # (optional) state management
└── services/                  # HTTP client to Node.js (API calls)
```

---

## 7. Repository Pattern — Base Repo (Node.js)

All repos extend a generic base for common CRUD operations:

```typescript
// repositories/baseRepo.ts
import { supabase } from '../config/supabase';

export class BaseRepo<T> {
  constructor(protected tableName: string) {}

  async findAll(filters?: Record<string, any>): Promise<T[]> {
    let query = supabase.from(this.tableName).select('*');
    if (filters) {
      for (const [key, value] of Object.entries(filters)) {
        query = query.eq(key, value);
      }
    }
    const { data, error } = await query;
    if (error) throw error;
    return data as T[];
  }

  async findOne(id: string): Promise<T | null> {
    const { data, error } = await supabase
      .from(this.tableName)
      .select('*')
      .eq('id', id)
      .single();
    if (error) throw error;
    return data as T;
  }

  async insert(data: Partial<T>): Promise<T> {
    const { data: result, error } = await supabase
      .from(this.tableName)
      .insert(data)
      .select()
      .single();
    if (error) throw error;
    return result as T;
  }

  async update(id: string, data: Partial<T>): Promise<T> {
    const { data: result, error } = await supabase
      .from(this.tableName)
      .update(data)
      .eq('id', id)
      .select()
      .single();
    if (error) throw error;
    return result as T;
  }

  async delete(id: string): Promise<void> {
    const { error } = await supabase
      .from(this.tableName)
      .delete()
      .eq('id', id);
    if (error) throw error;
  }
}
```

**Example concrete repo:**
```typescript
// repositories/inventoryRepo.ts
import { BaseRepo } from './baseRepo';
import { Inventory } from '../../shared/types';

export class InventoryRepo extends BaseRepo<Inventory> {
  constructor() {
    super('inventory');
  }

  async findByIngredientId(ingredientId: string): Promise<Inventory | null> {
    const { data, error } = await supabase
      .from('inventory')
      .select('*')
      .eq('ingredient_id', ingredientId)
      .single();
    if (error) throw error;
    return data;
  }

  async findLowStock(): Promise<Inventory[]> {
    // Custom query joining ingredients for reorder_threshold
    const { data, error } = await supabase
      .from('inventory')
      .select('*, ingredients(name, unit, reorder_threshold)')
      .lt('quantity_grams', supabase.raw('ingredients.reorder_threshold'));
    if (error) throw error;
    return data;
  }

  // Deduction is handled by fifoBatchService using inventoryBatchRepo,
  // then this snapshot row is updated to keep dashboard reads fast.
}

export const inventoryRepo = new InventoryRepo();
```

---

## 8. Service Pattern Example (Node.js)

```typescript
// services/inventoryService.ts
import { inventoryRepo } from '../repositories/inventoryRepo';
import { inventoryLogRepo } from '../repositories/inventoryLogRepo';
import { recipeRepo } from '../repositories/recipeRepo';
import { systemLogRepo } from '../repositories/systemLogRepo';
import { ApiError } from '../utils/apiError';

export async function restock(ingredientId: string, addedGrams: number, reason: string) {
  // Business rule: can't restock negative amount
  if (addedGrams <= 0) {
    throw new ApiError(400, 'Restock amount must be positive');
  }

  // Repo call — no direct Supabase
  const current = await inventoryRepo.findByIngredientId(ingredientId);
  if (!current) throw new ApiError(404, 'Inventory not found');

  // In Module 3, restock creates an inventory_batches row with expiry_date,
  // then updates this inventory snapshot total.

  await inventoryLogRepo.insert({
    inventory_id: current.id,
    change_grams: addedGrams,
    reason,
  } as any);
}
```

---

## 9. What Goes Where (Quick Reference)

| Code | Layer | Why |
|---|---|---|
| `supabase.from('inventory').select(...)` | Repo | DB access |
| `if (addedGrams <= 0) throw ApiError` | Service | Business rule |
| `min(have / grams_per_unit)` calculation | Service | Business logic |
| `router.get('/inventory', handler)` | Controller | HTTP routing |
| `z.object({ quantity: z.number() })` | Model | Data shape |
| `res.json(data)` | Controller | Response formatting |
| `fastApiMlClient.predict(request)` | TypeScript external adapter called by Service | Typed ML orchestration |
| `SELECT * WHERE quantity < threshold` | Repo | DB query |
| Random Forest training | Service (Python) | Business logic |
| Loading joblib file | `ModelArtifactStore` (Python infrastructure) | Artifact access |
| `supabase.from('daily_sales_records').select(...)` | TypeScript Repo | DB access |
| `@router.post('/predict')` | FastAPI route module | Thin validation/delegation |

---

## 10. Module Conformance

Each module plan must conform to this architecture:

| Module | Repos Added | Services Added |
|---|---|---|
| Module 0 (Data Foundation) | — | — (just schema + seed) |
| Module 1 (Node.js) | BaseRepo, bakerySettingsRepo, weatherRepo, calendarRepo, systemLogRepo, notificationRepo, deviceTokenRepo | ContextService, notification/access/settings services, `PredictionOrchestrationService`, `ModelManagementService`; adapters include `FastApiMlClient` |
| Module 2 (ML Server) | None — FastAPI has no database Repos | `PredictionService`, `FeaturePreparationService`, `ModelTrainingService`, `ModelEvaluationService`, `ConfidenceService`, `ColdStartService`, `ModelArtifactStore` |
| Module 3 (Inventory) | inventoryRepo, inventoryBatchRepo, inventoryLogRepo, productionDecisionRepo, recipeRepo, ingredientRepo, dailyResultRepo, donationRepo, breadCategoryRepo | InventoryService, FIFO batch service, inventory quality service, ProductionDecisionService, recipe service, RecommendationEngine, weekly summary service, ingredient cost calculator |
| Module 4 (POS) | salesTransactionRepo, dailyProductionRepo, dailyResultRepo, dailySalesRecordRepo | `PosSimulationService`, `TransactionRecordingService`, sales-distribution service |
| Module 5 (Donation+Dashboard) | donationRepo, wasteRepo, charityPartnerRepo | `LeftoverManagementService`, DashboardService, ReportService, financial summary service |
| Module 6 (Operation Reminders + Testing) | — | operationReminderService (emits reminders only; does not run prediction/simulation), test suites |

**Finance Decoupling Rule**

`ingredientCostCalculator.ts` and `financialSummaryService.ts` are reporting-only. They may read recipes, ingredient costs, cached `daily_results.revenue`, `daily_results.ingredient_cost`, `daily_results.gross_profit`, and `sales_transactions.subtotal` for dashboard summaries.

They must not be imported by `recommendationEngine.ts`, `constraintChecker.ts`, or the Python ML server. The recommendation path remains:

```text
ML predicted demand -> recipes/inventory grams -> constraints -> manager recommendation
```

Finance remains:

```text
POS results -> cached revenue/cost/profit -> dashboard reporting
```

---

**Document Status:** Authoritative. All module plans reference and conform to this architecture.
