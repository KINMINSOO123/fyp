# Module 3: Inventory + Integration — Detailed Plan

**Build Order:** 4th (depends on Module 0, Module 1, Module 2)
**Status:** Detailed plan — ready for implementation
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan (sub-modules, endpoints, signature feature, file structure).
> This README documents the concrete artifacts to build: repo queries, service logic, route handlers, request/response flow, verification.

## Revision baseline (authoritative)

- `RecommendationEngine` reads a stored `DailyPrediction` through `DailyPredictionRepo`; it never calls FastAPI or raw HTTP. Missing prediction is a validation error handled through the normal Controller → Service chain.
- Only `PredictionOrchestrationService` and `ModelManagementService` call `FastApiMlClient`.
- TypeScript Controllers, Services and Repos are classes; Express router files are thin modules.
- Confirming a production decision still does not deduct inventory. The POS simulation validates inventory and deducts FIFO exactly once before sales; later failure rolls back or reverses that deduction.
- Weekly reporting remains planned, with PDF/CSV export owned by Module 5 reporting rather than the recommendation path.

Any older function-style or direct-ML fallback snippet below is subordinate to these rules.

---

## 1. Dependencies (from Modules 0, 1, 2)

| Artifact | Used For |
|---|---|
| Module 0 schema: `inventory`, `inventory_batches`, `inventory_log`, `recipes`, `ingredients`, `bread_categories` | CRUD + FIFO business logic |
| Module 0 schema: `production_decisions`, `daily_production`, `daily_results`, `donations` | Manager decision capture + weekly summary aggregation |
| Module 0 `shared/types.ts` | Zod schemas for request/response validation (Model layer) |
| Module 1 Express app, auth middleware, Supabase client | This module extends the existing backend (repos use Supabase client) |
| Module 1 `controllers/index.ts` | Register new controllers here |
| Module 1 `repositories/baseRepo.ts` | Base class new repos extend |
| Module 2 prediction output | `RecommendationEngine` reads the stored `DailyPrediction` through `DailyPredictionRepo`; only `PredictionOrchestrationService` calls FastAPI through `FastApiMlClient` |

---

## 2. Artifacts to Build

> Layered per `../ARCHITECTURE.md`. Repos = Supabase only. Services = business logic + call repos. Controllers = thin HTTP handlers.

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `backend/src/repositories/inventoryRepo.ts` | Repo | inventory snapshot CRUD + findLowStock |
| 2 | `backend/src/repositories/inventoryBatchRepo.ts` | Repo | FIFO batch CRUD + findUsableByIngredient + findExpiringSoon |
| 3 | `backend/src/repositories/inventoryLogRepo.ts` | Repo | inventory_log table CRUD |
| 4 | `backend/src/repositories/productionDecisionRepo.ts` | Repo | production_decisions CRUD + findByDate |
| 5 | `backend/src/repositories/recipeRepo.ts` | Repo | recipes table CRUD + findByCategory |
| 6 | `backend/src/repositories/ingredientRepo.ts` | Repo | ingredients table |
| 7 | `backend/src/repositories/dailyResultRepo.ts` | Repo | daily_results (for weekly summary) |
| 8 | `backend/src/repositories/donationRepo.ts` | Repo | donations (for weekly summary) |
| 9 | `backend/src/repositories/breadCategoryRepo.ts` | Repo | bread_categories |
| 10 | `backend/src/repositories/dailyPredictionRepo.ts` | Repo | `daily_predictions` (read stored `DailyPrediction`) |
| 11 | `backend/src/services/recipeService.ts` | Service | Recipe business logic (calls recipeRepo) |
| 12 | `backend/src/services/ingredientCalculator.ts` | Service | Compute requirements + max_producible (pure calc) |
| 13 | `backend/src/services/constraintChecker.ts` | Service | Detect insufficient ingredients (pure calc) |
| 14 | `backend/src/services/fifoBatchService.ts` | Service | FIFO deduction, batch discard/expiry, snapshot sync helper |
| 15 | `backend/src/services/inventoryQualityService.ts` | Service | Expired active batches, snapshot mismatch, negative quantity, missing recipe checks |
| 16 | `backend/src/services/inventoryService.ts` | Service | Restock, auto-deduct, low-stock/expiry alerts (calls repos) |
| 17 | `backend/src/services/productionDecisionService.ts` | Service | Confirm manager final quantity, enforce feasibility/reason rules, and audit without deducting inventory |
| 18 | `backend/src/services/recommendationEngine.ts` | Service | THE signature feature (calls Repos only; never FastAPI) |
| 19 | `backend/src/services/weeklySummaryService.ts` | Service | Aggregated waste/trend per category (calls repos) |
| 19b | `backend/src/services/ingredientCostCalculator.ts` | Service | **Reporting-only.** `costPerUnit(categoryId)` = Σ(recipe grams × ingredient cost per gram). Used by Module 4 (`daily_results.ingredient_cost`) and Module 5 dashboard. NEVER imported by recommendationEngine/constraintChecker. |
| 20 | `backend/src/controllers/inventoryController.ts` | Controller | Inventory endpoints (fills Module 1 stub) |
| 21 | `backend/src/controllers/recipeController.ts` | Controller | Recipe endpoints |
| 22 | `backend/src/controllers/recommendationController.ts` | Controller | Smart recommendation + production-decision endpoint |
| 23 | `backend/src/controllers/summaryController.ts` | Controller | Weekly summary endpoint |
| 24 | Update `backend/src/controllers/index.ts` | Controller | Register the 4 new controller files |

---

## 3. Shared Types (add to `backend/shared/types.ts`)

```typescript
// Recipe map: category name → ingredient name → grams per unit
export type RecipeMap = Record<string, Record<string, number>>;

// Inventory map: ingredient name → quantity in grams
export type InventoryMap = Record<string, number>;

// Inventory item with metadata (for list view)
export const InventoryItemSchema = z.object({
  id: z.string().uuid(),
  ingredient_id: z.string().uuid(),
  ingredient_name: z.string(),
  quantity_grams: z.number(),
  unit: z.string(),
  reorder_threshold: z.number().nullable(),
  is_low_stock: z.boolean(),
  updated_at: z.string(),
});
export type InventoryItem = z.infer<typeof InventoryItemSchema>;

// FIFO ingredient batch
export const InventoryBatchSchema = z.object({
  id: z.string().uuid(),
  ingredient_id: z.string().uuid(),
  ingredient_name: z.string().optional(),
  received_date: z.string(),
  expiry_date: z.string(),
  initial_quantity_grams: z.number(),
  remaining_quantity_grams: z.number(),
  source: z.string().nullable().optional(),
  status: z.enum(['active', 'depleted', 'expired', 'discarded']),
  created_at: z.string(),
});
export type InventoryBatch = z.infer<typeof InventoryBatchSchema>;

export const ExpiringBatchAlertSchema = InventoryBatchSchema.extend({
  days_until_expiry: z.number().int(),
  severity: z.enum(['critical', 'warning', 'info']),
});
export type ExpiringBatchAlert = z.infer<typeof ExpiringBatchAlertSchema>;

export const InventoryQualityIssueSchema = z.object({
  code: z.enum(['expired_active_batch', 'snapshot_mismatch', 'negative_quantity', 'missing_recipe_ingredient']),
  severity: z.enum(['critical', 'warning', 'info']),
  message: z.string(),
  ingredient_id: z.string().uuid().optional(),
  bread_category_id: z.string().uuid().optional(),
  batch_id: z.string().uuid().optional(),
});
export type InventoryQualityIssue = z.infer<typeof InventoryQualityIssueSchema>;

export const ProductionDecisionSchema = z.object({
  id: z.string().uuid(),
  target_date: z.string(),
  bread_category_id: z.string().uuid(),
  prediction_id: z.string().uuid().nullable(),
  predicted_demand: z.number().int(),
  recommended_production: z.number().int(),
  max_producible: z.number().int().nonnegative(),
  final_selected_qty: z.number().int(),
  selected_option: z.enum(['full_prediction', 'reduced_due_constraint', 'manual_override']),
  decision_reason: z.string().nullable(),
  confirmed_by: z.string().uuid().nullable(),
  confirmed_at: z.string(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type ProductionDecision = z.infer<typeof ProductionDecisionSchema>;

// Ingredient requirement for a production quantity
export const IngredientRequirementSchema = z.object({
  ingredient_id: z.string().uuid(),
  ingredient_name: z.string(),
  grams_per_unit: z.number(),
  units: z.number().int(),
  total_grams: z.number(),
  have_grams: z.number(),
  sufficient: z.boolean(),
});
export type IngredientRequirement = z.infer<typeof IngredientRequirementSchema>;

// Constraint detected during checking
export const ConstraintSchema = z.object({
  ingredient_id: z.string().uuid(),
  ingredient_name: z.string(),
  have_grams: z.number(),
  need_grams: z.number(),
  shortfall_grams: z.number(),
  max_producible_with_this: z.number().int(),
});
export type Constraint = z.infer<typeof ConstraintSchema>;

// Recommendation option for the baker
export const RecommendationOptionSchema = z.object({
  id: z.number().int(),
  action: z.enum(['produce_reduced', 'order_ingredients']),
  production_qty: z.number().int(),
  order_items: z.array(z.object({
    ingredient: z.string(),
    grams: z.number(),
  })).optional(),
  note: z.string(),
  recommended: z.boolean(),
});
export type RecommendationOption = z.infer<typeof RecommendationOptionSchema>;

// Full category recommendation
export const CategoryRecommendationSchema = z.object({
  bread_category_id: z.string().uuid(),
  category_name: z.string(),
  predicted_demand: z.number().int(),
  confidence: z.number(),
  recommended_production: z.number().int(),
  max_producible: z.number().int().nonnegative(),
  ingredient_requirements: z.array(IngredientRequirementSchema),
  constraints: z.array(ConstraintSchema),
  options: z.array(RecommendationOptionSchema),
});
export type CategoryRecommendation = z.infer<typeof CategoryRecommendationSchema>;

// Weekly summary per category
export const CategoryWeeklySummarySchema = z.object({
  bread_category_id: z.string().uuid(),
  category_name: z.string(),
  total_produced: z.number().int(),
  total_sold: z.number().int(),
  total_leftover: z.number().int(),
  total_donated: z.number().int(),
  avg_waste_rate: z.number(),
  prev_week_waste_rate: z.number().nullable(),
  trend: z.enum(['improving', 'stable', 'worsening']),
  // Reporting-only financial aggregates (summed from cached daily_results for the week)
  total_revenue: z.number().nonnegative(),
  total_ingredient_cost: z.number().nonnegative(),
  total_gross_profit: z.number(),
});
export type CategoryWeeklySummary = z.infer<typeof CategoryWeeklySummarySchema>;
```

---

## 4. Repositories (Repo Layer — Supabase only)

> Repos do ONLY Supabase queries. No business logic, no validation. See `../ARCHITECTURE.md` §4.2. All extend `baseRepo.ts` from Module 1.

### 4.1 `src/repositories/inventoryRepo.ts`
```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { Inventory } from '../../shared/types';

export class InventoryRepo extends BaseRepo<Inventory> {
  constructor() { super('inventory'); }

  async findByIngredientId(ingredientId: string): Promise<Inventory | null> {
    const { data, error } = await supabase
      .from('inventory').select('id, ingredient_id, quantity_grams, updated_at')
      .eq('ingredient_id', ingredientId).single();
    if (error) throw error;
    return data;
  }

  async findAllWithIngredients(): Promise<any[]> {
    const { data, error } = await supabase
      .from('inventory').select(
        'id, ingredient_id, quantity_grams, updated_at, ingredients(name, unit, reorder_threshold)'
      );
    if (error) throw error;
    return data;
  }

  async findLowStock(): Promise<any[]> {
    const { data, error } = await supabase.rpc('get_low_stock_items');
    if (error) throw error;
    return data ?? [];
  }
}
export const inventoryRepo = new InventoryRepo();
```

### 4.2 `src/repositories/inventoryBatchRepo.ts`
```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';

export class InventoryBatchRepo extends BaseRepo<any> {
  constructor() { super('inventory_batches'); }

  async findUsableByIngredient(ingredientId: string, asOfDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('inventory_batches')
      .select('id, ingredient_id, received_date, expiry_date, remaining_quantity_grams, status')
      .eq('ingredient_id', ingredientId)
      .eq('status', 'active')
      .gt('remaining_quantity_grams', 0)
      .gte('expiry_date', asOfDate)
      .order('expiry_date', { ascending: true })
      .order('received_date', { ascending: true });
    if (error) throw error;
    return data ?? [];
  }

  async findByFilters(filters: {
    ingredientId?: string;
    status?: string;
    expiringBefore?: string;
  }): Promise<any[]> {
    let query = supabase
      .from('inventory_batches')
      .select('id, ingredient_id, received_date, expiry_date, initial_quantity_grams, remaining_quantity_grams, source, status, created_at, ingredients(name, unit)')
      .order('expiry_date', { ascending: true });
    if (filters.ingredientId) query = query.eq('ingredient_id', filters.ingredientId);
    if (filters.status) query = query.eq('status', filters.status);
    if (filters.expiringBefore) query = query.lte('expiry_date', filters.expiringBefore);
    const { data, error } = await query;
    if (error) throw error;
    return data ?? [];
  }

  async findExpiringSoon(untilDate: string): Promise<any[]> {
    return this.findByFilters({ status: 'active', expiringBefore: untilDate });
  }
}
export const inventoryBatchRepo = new InventoryBatchRepo();
```

### 4.3 `src/repositories/inventoryLogRepo.ts`
```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';

export class InventoryLogRepo extends BaseRepo<any> {
  constructor() { super('inventory_log'); }

  async findByFilters(filters: { reason?: string; dateFrom?: string; dateTo?: string }): Promise<any[]> {
    let query = supabase.from('inventory_log').select(
      'id, batch_id, change_grams, reason, effective_date, created_at, inventory(ingredient_id, ingredients(name)), inventory_batches(expiry_date)'
    ).order('effective_date', { ascending: false });
    if (filters.reason) query = query.eq('reason', filters.reason);
    if (filters.dateFrom) query = query.gte('effective_date', filters.dateFrom);
    if (filters.dateTo) query = query.lte('effective_date', filters.dateTo);
    const { data, error } = await query;
    if (error) throw error;
    return data;
  }

  async findMovementsUntil(asOfDate: string): Promise<any[]> {
    const { data, error } = await supabase.from('inventory_log').select(
      'inventory_id, change_grams, effective_date, inventory(ingredient_id, ingredients(name))'
    ).lte('effective_date', asOfDate).order('effective_date', { ascending: true });
    if (error) throw error;
    return data;
  }
}
export const inventoryLogRepo = new InventoryLogRepo();
```

### 4.4 `src/repositories/productionDecisionRepo.ts`
```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';

export class ProductionDecisionRepo extends BaseRepo<any> {
  constructor() { super('production_decisions'); }

  async findByDate(targetDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('production_decisions')
      .select('*, bread_categories(name)')
      .eq('target_date', targetDate)
      .order('created_at', { ascending: true });
    if (error) throw error;
    return data ?? [];
  }

  async upsertDecision(decision: any): Promise<any> {
    const { data, error } = await supabase
      .from('production_decisions')
      .upsert(decision, { onConflict: 'target_date,bread_category_id' })
      .select()
      .single();
    if (error) throw error;
    return data;
  }
}
export const productionDecisionRepo = new ProductionDecisionRepo();
```

### 4.5 `src/repositories/recipeRepo.ts`
```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';

export class RecipeRepo extends BaseRepo<any> {
  constructor() { super('recipes'); }

  async findAllWithNames(): Promise<any[]> {
    const { data, error } = await supabase
      .from('recipes').select(
        'bread_category_id, ingredient_id, grams_per_unit, ingredients(name), bread_categories(name)'
      ).order('display_order', { foreignTable: 'bread_categories', ascending: true });
    if (error) throw error;
    return data;
  }

  async findByCategory(categoryId: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('recipes').select('ingredient_id, grams_per_unit, ingredients(name)')
      .eq('bread_category_id', categoryId);
    if (error) throw error;
    return data;
  }

  async updateGramsPerUnit(categoryId: string, ingredientId: string, gramsPerUnit: number): Promise<void> {
    const { error } = await supabase
      .from('recipes').update({ grams_per_unit: gramsPerUnit })
      .eq('bread_category_id', categoryId).eq('ingredient_id', ingredientId);
    if (error) throw error;
  }
}
export const recipeRepo = new RecipeRepo();
```

### 4.6 `src/repositories/dailyResultRepo.ts`, `donationRepo.ts`, `breadCategoryRepo.ts`, `dailyPredictionRepo.ts`
```typescript
// dailyResultRepo.ts — for weekly summary
export class DailyResultRepo extends BaseRepo<any> {
  constructor() { super('daily_results'); }
  async findByDateRange(startDate: string, endDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('daily_results').select(
        'bread_category_id, produced, sold, leftover, waste_rate_pct, revenue, ingredient_cost, gross_profit, bread_categories(name)'
      ).gte('result_date', startDate).lte('result_date', endDate);
    if (error) throw error;
    return data;
  }
}
export const dailyResultRepo = new DailyResultRepo();

// donationRepo.ts — for weekly summary
export class DonationRepo extends BaseRepo<any> {
  constructor() { super('donations'); }
  async findByDateRange(startDate: string, endDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('donations').select('bread_category_id, quantity')
      .gte('donation_date', startDate).lte('donation_date', endDate);
    if (error) throw error;
    return data;
  }
}
export const donationRepo = new DonationRepo();

// dailyPredictionRepo.ts — read stored DailyPrediction for recommendation engine
export class PredictionRepo extends BaseRepo<any> {
  constructor() { super('daily_predictions'); }
  async findByDate(targetDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('daily_predictions').select('*').eq('target_date', targetDate);
    if (error) throw error;
    return data;
  }
}
export const predictionRepo = new PredictionRepo();
```

---

## 5. Services Layer (Service Layer — business logic, calls repos)

> Services contain business logic. They call repos for DB access. No direct Supabase calls. See `../ARCHITECTURE.md` §4.3.

### 5.1 `src/services/recipeService.ts`

```typescript
import { recipeRepo } from '../repositories/recipeRepo';
import { logger } from '../utils/logger';

export interface RecipeRow {
  ingredient_id: string;
  ingredient_name: string;
  grams_per_unit: number;
}

export async function getAllRecipes(): Promise<Record<string, RecipeRow[]>> {
  const data = await recipeRepo.findAllWithNames();  // Repo call
  const map: Record<string, RecipeRow[]> = {};
  for (const row of data) {
    const catName = row.bread_categories.name;
    if (!map[catName]) map[catName] = [];
    map[catName].push({
      ingredient_id: row.ingredient_id,
      ingredient_name: row.ingredients.name,
      grams_per_unit: row.grams_per_unit,
    });
  }
  return map;
}

export async function getRecipe(categoryId: string): Promise<RecipeRow[]> {
  const data = await recipeRepo.findByCategory(categoryId);  // Repo call
  return data.map(row => ({
    ingredient_id: row.ingredient_id,
    ingredient_name: row.ingredients.name,
    grams_per_unit: row.grams_per_unit,
  }));
}

export async function updateRecipe(
  categoryId: string,
  updates: { ingredient_id: string; grams_per_unit: number }[]
): Promise<void> {
  for (const u of updates) {
    await recipeRepo.updateGramsPerUnit(categoryId, u.ingredient_id, u.grams_per_unit);  // Repo call
  }
  logger.info('Recipe updated', { categoryId, updates });
}
```

### 5.2 `src/services/ingredientCalculator.ts`

```typescript
import { RecipeRow, getRecipe } from './recipeService';
import { InventoryMap } from '../../shared/types';

export interface IngredientRequirement {
  ingredient_id: string;
  ingredient_name: string;
  grams_per_unit: number;
  units: number;
  total_grams: number;
  have_grams: number;
  sufficient: boolean;
}

export async function calculateRequirements(
  categoryId: string,
  quantity: number,
  inventory: InventoryMap
): Promise<IngredientRequirement[]> {
  const recipe = await getRecipe(categoryId);
  return recipe.map(row => {
    const total_grams = row.grams_per_unit * quantity;
    const have_grams = inventory[row.ingredient_name] ?? 0;
    return {
      ingredient_id: row.ingredient_id,
      ingredient_name: row.ingredient_name,
      grams_per_unit: row.grams_per_unit,
      units: quantity,
      total_grams,
      have_grams,
      sufficient: have_grams >= total_grams,
    };
  });
}

export function calculateMaxProducible(
  recipe: RecipeRow[],
  inventory: InventoryMap
): number {
  // max_producible = min across ingredients of (have / grams_per_unit)
  const maxPerIngredient = recipe.map(row => {
    const have = inventory[row.ingredient_name] ?? 0;
    return Math.floor(have / row.grams_per_unit);
  });
  return Math.min(...maxPerIngredient);
}

export function calculateMaxProducibleFromRequirements(
  requirements: IngredientRequirement[]
): number {
  const maxPerIngredient = requirements.map(r =>
    Math.floor(r.have_grams / r.grams_per_unit)
  );
  return Math.min(...maxPerIngredient);
}
```

### 5.3 `src/services/constraintChecker.ts`

```typescript
import { IngredientRequirement, Constraint } from '../../shared/types';
import { calculateMaxProducibleFromRequirements } from './ingredientCalculator';

export interface CheckResult {
  constraints: Constraint[];
  max_producible: number;
  has_constraints: boolean;
}

export function checkConstraints(
  requirements: IngredientRequirement[]
): CheckResult {
  const constraints: Constraint[] = requirements
    .filter(r => !r.sufficient)
    .map(r => ({
      ingredient_id: r.ingredient_id,
      ingredient_name: r.ingredient_name,
      have_grams: r.have_grams,
      need_grams: r.total_grams,
      shortfall_grams: r.total_grams - r.have_grams,
      max_producible_with_this: Math.floor(r.have_grams / r.grams_per_unit),
    }));

  const max_producible = constraints.length > 0
    ? Math.min(...constraints.map(c => c.max_producible_with_this))
    : Math.min(...requirements.map(r => Math.floor(r.have_grams / r.grams_per_unit)));

  return {
    constraints,
    max_producible,
    has_constraints: constraints.length > 0,
  };
}
```

### 5.4 `src/services/fifoBatchService.ts`

```typescript
import { inventoryBatchRepo } from '../repositories/inventoryBatchRepo';
import { inventoryRepo } from '../repositories/inventoryRepo';
import { inventoryLogRepo } from '../repositories/inventoryLogRepo';
import { ApiError } from '../utils/apiError';

export interface FifoDeduction {
  batch_id: string;
  ingredient_id: string;
  expiry_date: string;
  deducted_grams: number;
}

export async function createRestockBatch(input: {
  ingredientId: string;
  addedGrams: number;
  receivedDate: string;
  expiryDate: string;
  effectiveDate?: string;
  source?: string;
  reason: string;
}): Promise<void> {
  const inv = await inventoryRepo.findByIngredientId(input.ingredientId);
  if (!inv) throw new ApiError(404, 'Inventory not found');

  const batch = await inventoryBatchRepo.insert({
    ingredient_id: input.ingredientId,
    received_date: input.receivedDate,
    expiry_date: input.expiryDate,
    initial_quantity_grams: input.addedGrams,
    remaining_quantity_grams: input.addedGrams,
    source: input.source ?? null,
    status: 'active',
  } as any);

  await inventoryRepo.update(inv.id, {
    quantity_grams: inv.quantity_grams + input.addedGrams,
  } as any);

  await inventoryLogRepo.insert({
    inventory_id: inv.id,
    batch_id: batch.id,
    change_grams: input.addedGrams,
    reason: input.reason,
    effective_date: input.effectiveDate ?? input.receivedDate,
  } as any);
}

export async function deductFifo(input: {
  ingredientId: string;
  gramsNeeded: number;
  asOfDate: string;
  reason: string;
}): Promise<FifoDeduction[]> {
  const inv = await inventoryRepo.findByIngredientId(input.ingredientId);
  if (!inv) throw new ApiError(404, 'Inventory not found');
  if (inv.quantity_grams < input.gramsNeeded) {
    throw new ApiError(400, 'Insufficient inventory');
  }

  const batches = await inventoryBatchRepo.findUsableByIngredient(input.ingredientId, input.asOfDate);
  const usableTotal = batches.reduce((sum, batch) => sum + batch.remaining_quantity_grams, 0);
  if (usableTotal < input.gramsNeeded) {
    throw new ApiError(400, 'Insufficient non-expired FIFO batch quantity');
  }

  let remaining = input.gramsNeeded;
  const deductions: FifoDeduction[] = [];

  for (const batch of batches) {
    if (remaining <= 0) break;
    const take = Math.min(batch.remaining_quantity_grams, remaining);
    const newRemaining = batch.remaining_quantity_grams - take;

    await inventoryBatchRepo.update(batch.id, {
      remaining_quantity_grams: newRemaining,
      status: newRemaining === 0 ? 'depleted' : 'active',
    } as any);

    await inventoryLogRepo.insert({
      inventory_id: inv.id,
      batch_id: batch.id,
      change_grams: -take,
      reason: input.reason,
      effective_date: input.asOfDate,
    } as any);

    deductions.push({
      batch_id: batch.id,
      ingredient_id: input.ingredientId,
      expiry_date: batch.expiry_date,
      deducted_grams: take,
    });
    remaining -= take;
  }

  await inventoryRepo.update(inv.id, {
    quantity_grams: inv.quantity_grams - input.gramsNeeded,
  } as any);

  return deductions;
}

export async function discardBatch(batchId: string, reason = 'spoilage'): Promise<void> {
  const batch = await inventoryBatchRepo.findOne(batchId);
  if (!batch || batch.status !== 'active') throw new ApiError(404, 'Active batch not found');

  const inv = await inventoryRepo.findByIngredientId(batch.ingredient_id);
  if (!inv) throw new ApiError(404, 'Inventory not found');

  await inventoryBatchRepo.update(batch.id, {
    remaining_quantity_grams: 0,
    status: 'discarded',
  } as any);
  await inventoryRepo.update(inv.id, {
    quantity_grams: Math.max(0, inv.quantity_grams - batch.remaining_quantity_grams),
  } as any);
  await inventoryLogRepo.insert({
    inventory_id: inv.id,
    batch_id: batch.id,
    change_grams: -batch.remaining_quantity_grams,
    reason,
    effective_date: new Date().toISOString().split('T')[0],
  } as any);
}
```

### 5.5 `src/services/inventoryQualityService.ts`

```typescript
import { inventoryRepo } from '../repositories/inventoryRepo';
import { inventoryBatchRepo } from '../repositories/inventoryBatchRepo';
import { recipeRepo } from '../repositories/recipeRepo';
import { breadCategoryRepo } from '../repositories/breadCategoryRepo';
import { ingredientRepo } from '../repositories/ingredientRepo';
import { InventoryQualityIssue } from '../../shared/types';

export async function runInventoryQualityChecks(asOfDate: string): Promise<InventoryQualityIssue[]> {
  const issues: InventoryQualityIssue[] = [];
  const [inventory, activeBatches, recipes, categories, ingredients] = await Promise.all([
    inventoryRepo.findAllWithIngredients(),
    inventoryBatchRepo.findByFilters({ status: 'active' }),
    recipeRepo.findAllWithNames(),
    breadCategoryRepo.findAll({ is_active: true } as any),
    ingredientRepo.findAll(),
  ]);

  for (const batch of activeBatches) {
    if (batch.expiry_date < asOfDate && batch.remaining_quantity_grams > 0) {
      issues.push({
        code: 'expired_active_batch',
        severity: 'critical',
        message: `${batch.ingredients.name} has an expired active batch`,
        ingredient_id: batch.ingredient_id,
        batch_id: batch.id,
      });
    }
  }

  for (const item of inventory) {
    if (item.quantity_grams < 0) {
      issues.push({
        code: 'negative_quantity',
        severity: 'critical',
        message: `${item.ingredients.name} inventory is negative`,
        ingredient_id: item.ingredient_id,
      });
    }

    const batchTotal = activeBatches
      .filter(b => b.ingredient_id === item.ingredient_id && b.expiry_date >= asOfDate)
      .reduce((sum, b) => sum + b.remaining_quantity_grams, 0);
    if (Math.abs(batchTotal - item.quantity_grams) > 1) {
      issues.push({
        code: 'snapshot_mismatch',
        severity: 'warning',
        message: `${item.ingredients.name} snapshot does not match usable FIFO batch total`,
        ingredient_id: item.ingredient_id,
      });
    }
  }

  for (const category of categories) {
    const recipeRows = recipes.filter(r => r.bread_category_id === category.id);
    for (const ingredient of ingredients) {
      if (!recipeRows.some(r => r.ingredient_id === ingredient.id)) {
        issues.push({
          code: 'missing_recipe_ingredient',
          severity: 'info',
          message: `${category.name} has no recipe row for ${ingredient.name}`,
          bread_category_id: category.id,
          ingredient_id: ingredient.id,
        });
      }
    }
  }

  return issues;
}
```

### 5.6 `src/services/inventoryService.ts`

```typescript
import { inventoryRepo } from '../repositories/inventoryRepo';
import { inventoryBatchRepo } from '../repositories/inventoryBatchRepo';
import { inventoryLogRepo } from '../repositories/inventoryLogRepo';
import { ingredientRepo } from '../repositories/ingredientRepo';
import { systemLogRepo } from '../repositories/systemLogRepo';
import { logger } from '../utils/logger';
import { getRecipe } from './recipeService';
import * as fifoBatchService from './fifoBatchService';
import { runInventoryQualityChecks } from './inventoryQualityService';
import { ApiError } from '../utils/apiError';

export interface InventoryItem {
  id: string;
  ingredient_id: string;
  ingredient_name: string;
  quantity_grams: number;
  unit: string;
  reorder_threshold: number | null;
  is_low_stock: boolean;
  updated_at: string;
}

export async function getInventory(): Promise<InventoryItem[]> {
  const data = await inventoryRepo.findAllWithIngredients();  // Repo call
  return data.map(row => ({
    id: row.id,
    ingredient_id: row.ingredient_id,
    ingredient_name: row.ingredients.name,
    quantity_grams: row.quantity_grams,
    unit: row.ingredients.unit,
    reorder_threshold: row.ingredients.reorder_threshold,
    is_low_stock: row.ingredients.reorder_threshold !== null
      && row.quantity_grams < row.ingredients.reorder_threshold,
    updated_at: row.updated_at,
  }));
}

export async function getInventoryMap(): Promise<Record<string, number>> {
  const items = await getInventory();
  const map: Record<string, number> = {};
  for (const item of items) {
    map[item.ingredient_name] = item.quantity_grams;
  }
  return map;
}

export async function getInventoryMapAsOf(asOfDate: string): Promise<Record<string, number>> {
  const movements = await inventoryLogRepo.findMovementsUntil(asOfDate);
  const map: Record<string, number> = {};

  for (const movement of movements) {
    const ingredientName = movement.inventory?.ingredients?.name;
    if (!ingredientName) continue;
    map[ingredientName] = (map[ingredientName] ?? 0) + Number(movement.change_grams);
  }

  return map;
}

export async function getInventoryMapForDate(targetDate: string): Promise<Record<string, number>> {
  const today = new Date().toISOString().split('T')[0];
  return targetDate < today
    ? getInventoryMapAsOf(targetDate)
    : getInventoryMap();
}

export async function restock(
  ingredientId: string,
  addedGrams: number,
  expiryDate: string,
  receivedDate: string = new Date().toISOString().split('T')[0],
  source?: string,
  reason: string = 'manual_restock'
): Promise<void> {
  // Business rule: can't restock negative amount
  if (addedGrams <= 0) {
    throw new ApiError(400, 'Restock amount must be positive');
  }

  // Create FIFO batch, update inventory snapshot, and log the batch movement.
  await fifoBatchService.createRestockBatch({
    ingredientId,
    addedGrams,
    receivedDate,
    expiryDate,
    source,
    reason,
    effectiveDate: receivedDate,
  });

  logger.info('Inventory restocked as FIFO batch', { ingredientId, addedGrams, expiryDate });
}

export async function deductForProduction(
  categoryId: string,
  unitsProduced: number,
  productionDate: string = new Date().toISOString().split('T')[0]
): Promise<void> {
  const recipe = await getRecipe(categoryId);  // Service call (which calls recipeRepo)

  for (const row of recipe) {
    const usage = row.grams_per_unit * unitsProduced;

    // Deduct from oldest non-expired batch first, then update snapshot/log.
    await fifoBatchService.deductFifo({
      ingredientId: row.ingredient_id,
      gramsNeeded: usage,
      asOfDate: productionDate,
      reason: 'daily_production',
    });

    const inv = await inventoryRepo.findByIngredientId(row.ingredient_id);
    const newQty = inv?.quantity_grams ?? 0;

    await checkAndLogLowStock(row.ingredient_id, row.ingredient_name, newQty);
  }

  logger.info('Ingredients deducted for production', { categoryId, unitsProduced });
}

// NEW (Module 4): Reverse a production deduction — adds ingredients back.
// Used by POS simulation re-simulation (forceRefresh) to restore inventory
// before deleting and re-inserting the day's data.
export async function reverseProductionDeduction(
  categoryId: string,
  unitsProduced: number,
  productionDate: string
): Promise<void> {
  // MVP reversal: add ingredients back as correction batches.
  // Future enhancement: query inventory_log by production id and restore exact batch movements.
  const recipe = await getRecipe(categoryId);  // Service call (which calls recipeRepo)

  for (const row of recipe) {
    const usage = row.grams_per_unit * unitsProduced;
    const expiry = new Date(productionDate);
    expiry.setDate(expiry.getDate() + 7);
    await fifoBatchService.createRestockBatch({
      ingredientId: row.ingredient_id,
      addedGrams: usage,
      receivedDate: productionDate,
      expiryDate: expiry.toISOString().split('T')[0],
      source: 're-simulation reversal',
      reason: 'reversal_re_simulation',
      effectiveDate: productionDate,
    });
  }

  logger.info('Ingredients restored (re-simulation reversal)', { categoryId, unitsProduced });
}

export async function getLowStockItems(): Promise<InventoryItem[]> {
  const items = await getInventory();
  return items.filter(i => i.is_low_stock);
}

export async function getBatches(filters: {
  ingredientId?: string;
  status?: string;
  expiringBefore?: string;
}): Promise<any[]> {
  return inventoryBatchRepo.findByFilters(filters);
}

export async function getExpiringSoon(days = 7): Promise<any[]> {
  const until = new Date();
  until.setDate(until.getDate() + days);
  const today = new Date();
  const batches = await inventoryBatchRepo.findExpiringSoon(until.toISOString().split('T')[0]);
  return batches.map(batch => {
    const expiry = new Date(batch.expiry_date);
    const days_until_expiry = Math.ceil((expiry.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
    let severity: 'critical' | 'warning' | 'info' = 'info';
    if (days_until_expiry <= 0) severity = 'critical';
    else if (days_until_expiry <= 3) severity = 'warning';
    return { ...batch, days_until_expiry, severity };
  });
}

export async function discardBatch(batchId: string): Promise<void> {
  await fifoBatchService.discardBatch(batchId);
}

export async function getInventoryQuality(asOfDate = new Date().toISOString().split('T')[0]) {
  const issues = await runInventoryQualityChecks(asOfDate);
  return {
    as_of_date: asOfDate,
    status: issues.some(i => i.severity === 'critical') ? 'critical'
      : issues.some(i => i.severity === 'warning') ? 'warning'
      : 'ok',
    issues,
  };
}

async function checkAndLogLowStock(
  ingredientId: string,
  ingredientName: string,
  currentQty: number
): Promise<void> {
  const ingredient = await ingredientRepo.findOne(ingredientId);  // Repo call
  if (ingredient?.reorder_threshold !== null && currentQty < ingredient.reorder_threshold) {
    await systemLogRepo.insert({  // Repo call
      event_type: 'low_stock_alert',
      payload: { ingredient: ingredientName, current: currentQty, threshold: ingredient.reorder_threshold },
      severity: 'warn',
    } as any);
    logger.warn('Low stock alert', { ingredientName, currentQty, threshold: ingredient.reorder_threshold });
  }
}

export async function getInventoryLog(filters: {
  reason?: string;
  dateFrom?: string;
}): Promise<any[]> {
  return inventoryLogRepo.findByFilters(filters);  // Repo call
}
```

### 5.7 `src/services/productionDecisionService.ts`

```typescript
import { productionDecisionRepo } from '../repositories/productionDecisionRepo';
import { systemLogRepo } from '../repositories/systemLogRepo';
import { ApiError } from '../utils/apiError';

export async function saveProductionDecision(input: {
  target_date: string;
  bread_category_id: string;
  prediction_id?: string | null;
  predicted_demand: number;
  recommended_production: number;
  max_producible: number;
  final_selected_qty: number;
  selected_option: 'full_prediction' | 'reduced_due_constraint' | 'manual_override';
  decision_reason?: string | null;
  confirmed_by: string;
}) {
  if (input.final_selected_qty < 0) {
    throw new ApiError(400, 'Final selected quantity cannot be negative');
  }
  if (input.final_selected_qty > input.max_producible) {
    throw new ApiError(400, 'Final selected quantity exceeds maximum producible quantity');
  }
  if (
    input.selected_option === 'full_prediction'
    && input.final_selected_qty !== input.recommended_production
  ) {
    throw new ApiError(400, 'Accepting the recommendation requires final quantity to match recommended production');
  }
  if (
    input.selected_option === 'reduced_due_constraint'
    && input.final_selected_qty >= input.recommended_production
  ) {
    throw new ApiError(400, 'Reduced decision must be lower than recommended production');
  }
  if (
    input.selected_option !== 'full_prediction'
    && !input.decision_reason?.trim()
  ) {
    throw new ApiError(400, 'Reduced or overridden decisions require a reason');
  }

  const decision = await productionDecisionRepo.upsertDecision({
    ...input,
    confirmed_at: new Date().toISOString(),
  });

  await systemLogRepo.insert({
    event_type: 'production_decision_confirmed',
    severity: 'info',
    payload: {
      target_date: input.target_date,
      bread_category_id: input.bread_category_id,
      prediction_id: input.prediction_id ?? null,
      predicted_demand: input.predicted_demand,
      recommended_production: input.recommended_production,
      max_producible: input.max_producible,
      final_selected_qty: input.final_selected_qty,
      selected_option: input.selected_option,
      decision_reason: input.decision_reason ?? null,
      confirmed_by: input.confirmed_by,
    },
  } as any);

  // Important: confirmation records the manager's decision only.
  // It must not call inventoryService.deductForProduction().
  return decision;
}

export async function getProductionDecisions(targetDate: string) {
  return productionDecisionRepo.findByDate(targetDate);
}
```

### 5.8 `src/services/recommendationEngine.ts` — THE SIGNATURE FEATURE

> **Core philosophy guard:** this service works purely on **units + grams**. It must NOT import `ingredientCostCalculator`, must not read `bread_categories.selling_price` or `ingredients.unit_cost`, and `constraintChecker` must not either. Finance is reporting-only (see 5.8a). Audit: `rg "ingredientCostCalculator|selling_price|unit_cost" src/services/recommendationEngine.ts src/services/constraintChecker.ts` → zero hits.

```typescript
import { env } from '../config/env';
import { inventoryRepo } from '../repositories/inventoryRepo';
import { calculateRequirements, calculateMaxProducibleFromRequirements } from './ingredientCalculator';
import { checkConstraints } from './constraintChecker';
import { getInventoryMapForDate, getExpiringSoon, getInventoryQuality } from './inventoryService';
import { CategoryRecommendation, RecommendationOption } from '../../shared/types';

export interface FullRecommendation {
  date: string;
  categories: CategoryRecommendation[];
  low_stock_alerts: { ingredient: string; current: number; threshold: number }[];
  expiring_batches: any[];
  inventory_quality: any;
}

export async function generateRecommendation(targetDate: string): Promise<FullRecommendation> {
  // 1. Fetch prediction from Module 2 (ML Server)
  const predictResponse = await fetch(`${env.ML_SERVER_URL}/predict`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target_date: targetDate }),
  });
  const prediction = await predictResponse.json();
  // prediction = { date, predictions: [{ bread_category_id, category_name, predicted_demand, confidence }], model_version }

  // 2. Fetch inventory for the target date.
  // Past dates reconstruct stock from inventory_log.effective_date;
  // today/future dates use the current inventory snapshot.
  const inventory = await getInventoryMapForDate(targetDate);
  const inventoryQuality = await getInventoryQuality(targetDate);

  // 3. Process each category
  const categories: CategoryRecommendation[] = [];
  for (const pred of prediction.predictions) {
    // Calculate ingredient requirements
    const requirements = await calculateRequirements(
      pred.bread_category_id,
      pred.predicted_demand,
      inventory
    );

    // Check constraints
    const check = checkConstraints(requirements);

    let recommended_production = pred.predicted_demand;
    let options: RecommendationOption[] = [];

    if (check.has_constraints) {
      // CONSTRAINED — build 2 options
      recommended_production = check.max_producible;
      const missedSales = pred.predicted_demand - check.max_producible;

      options = [
        {
          id: 1,
          action: 'produce_reduced',
          production_qty: check.max_producible,
          note: `Produce ${check.max_producible} with available ingredients. May miss ${missedSales} sales.`,
          recommended: false,
        },
        {
          id: 2,
          action: 'order_ingredients',
          production_qty: pred.predicted_demand,
          order_items: check.constraints.map(c => ({
            ingredient: c.ingredient_name,
            grams: c.shortfall_grams,
          })),
          note: `Order ${check.constraints.map(c => `${c.shortfall_grams}g ${c.ingredient_name}`).join(', ')} tonight → produce full ${pred.predicted_demand} units.`,
          recommended: true,
        },
      ];
    }

    categories.push({
      bread_category_id: pred.bread_category_id,
      category_name: pred.category_name,
      predicted_demand: pred.predicted_demand,
      confidence: pred.confidence,
      recommended_production,
      max_producible: check.max_producible,
      ingredient_requirements: requirements,
      constraints: check.constraints,
      options,
    });
  }

  // 4. Fetch low-stock alerts (Repo call)
  const lowStock = await inventoryRepo.findLowStock();
  const expiring = await getExpiringSoon(7);

  return {
    date: targetDate,
    categories,
    low_stock_alerts: lowStock ?? [],
    expiring_batches: expiring,
    inventory_quality: inventoryQuality,
  };
}
```

### 5.8a `src/services/ingredientCostCalculator.ts` — REPORTING-ONLY

> **Core project philosophy guard:** This service is *reporting-only*. It must NOT be imported by `recommendationEngine.ts` or `constraintChecker.ts`. Its single consumer in production is Module 4's `transactionRecordingService` (to cache `daily_results.ingredient_cost` on PRODUCED units) and Module 5's `financialSummaryService` (dashboard). Audit: `rg "ingredientCostCalculator" src/services/recommendationEngine.ts src/services/constraintChecker.ts` → zero hits.

```typescript
import { recipeService, RecipeRow } from './recipeService';
import { ingredientRepo } from '../repositories/ingredientRepo';
import { logger } from '../utils/logger';

// Map commercial bulk unit -> grams it represents (recipes/inventory store grams).
// Used ONLY for the finance conversion cost_per_gram = unit_cost / gramsPerBaseUnit(unit).
const GRAMS_PER_BASE_UNIT: Record<string, number> = {
  'kg': 1000,
  'g': 1,
  'ml': 1,
};

export const ingredientCostCalculator = {
  // Cost per gram of an ingredient, derived from its commercial bulk unit + unit_cost.
  // Reporting only — never feeds production or recommendation logic.
  costPerGram(ingredient: { unit: string; unit_cost: number }): number {
    const factor = GRAMS_PER_BASE_UNIT[ingredient.unit] ?? 1;
    return (ingredient.unit_cost ?? 0) / factor;
  },

  // Ingredient cost to produce ONE unit of a bread category.
  // = Σ over recipe (grams_per_unit * costPerGram(ingredient)).
  // Returns 0 when price data is unseeded (graceful degradation — рекомендуется keeps existing behaviour).
  async costPerUnit(categoryId: string): Promise<number> {
    const recipe: RecipeRow[] = await recipeService.getRecipe(categoryId);
    if (recipe.length === 0) return 0;

    const ingredients = await ingredientRepo.findAll();
    const byId = new Map(ingredients.map(i => [i.id, i]));

    let total = 0;
    for (const row of recipe) {
      const ingr = byId.get(row.ingredient_id);
      if (!ingr) continue;
      total += row.grams_per_unit * this.costPerGram(ingr);
    }
    return Math.round(total * 10000) / 10000; // 4dp
  },

  // Total ingredient cost to PRODUCE n units (not sell — by design).
  // Used by Module 4 to write daily_results.ingredient_cost so wasted/donated bread's cost counts.
  async costForProduction(categoryId: string, producedQty: number): Promise<number> {
    return Math.round((await this.costPerUnit(categoryId)) * producedQty * 100) / 100;
  },
};
```

### 5.9 `src/services/weeklySummaryService.ts`

```typescript
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { donationRepo } from '../repositories/donationRepo';
import { CategoryWeeklySummary } from '../../shared/types';

export async function getWeeklySummary(weekStart: string): Promise<CategoryWeeklySummary[]> {
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 6);
  const weekEndStr = weekEnd.toISOString().split('T')[0];

  // Previous week for trend comparison
  const prevWeekStart = new Date(weekStart);
  prevWeekStart.setDate(prevWeekStart.getDate() - 7);
  const prevWeekStartStr = prevWeekStart.toISOString().split('T')[0];
  const prevWeekEnd = new Date(prevWeekStartStr);
  prevWeekEnd.setDate(prevWeekEnd.getDate() + 6);
  const prevWeekEndStr = prevWeekEnd.toISOString().split('T')[0];

  // Fetch this week's daily_results (Repo call)
  const thisWeek = await dailyResultRepo.findByDateRange(weekStart, weekEndStr);

  // Fetch prev week for trend (Repo call)
  const prevWeek = await dailyResultRepo.findByDateRange(prevWeekStartStr, prevWeekEndStr);

  // Fetch donations this week (Repo call)
  const donations = await donationRepo.findByDateRange(weekStart, weekEndStr);

  // Group by category
  const byCategory: Record<string, any> = {};
  for (const row of thisWeek) {
    const catId = row.bread_category_id;
    if (!byCategory[catId]) {
      byCategory[catId] = {
        bread_category_id: catId,
        category_name: row.bread_categories.name,
        total_produced: 0,
        total_sold: 0,
        total_leftover: 0,
        total_donated: 0,
        waste_rates: [],
        total_revenue: 0,          // reporting-only (cached from daily_results)
        total_ingredient_cost: 0, // reporting-only
        total_gross_profit: 0,     // reporting-only
      };
    }
    byCategory[catId].total_produced += row.produced;
    byCategory[catId].total_sold += row.sold;
    byCategory[catId].total_leftover += row.leftover;
    byCategory[catId].waste_rates.push(row.waste_rate_pct || 0);
    // Financial aggregates (cached on daily_results by Module 4 — no per-sale recompute)
    byCategory[catId].total_revenue         += row.revenue ?? 0;
    byCategory[catId].total_ingredient_cost += row.ingredient_cost ?? 0;
    byCategory[catId].total_gross_profit    += row.gross_profit ?? 0;
  }

  // Add donations
  if (donations) {
    for (const d of donations) {
      if (byCategory[d.bread_category_id]) {
        byCategory[d.bread_category_id].total_donated += d.quantity;
      }
    }
  }

  // Compute prev week avg waste per category
  const prevWasteByCat: Record<string, number[]> = {};
  for (const row of prevWeek || []) {
    if (!prevWasteByCat[row.bread_category_id]) prevWasteByCat[row.bread_category_id] = [];
    prevWasteByCat[row.bread_category_id].push(row.waste_rate_pct || 0);
  }

  // Build summaries
  return Object.values(byCategory).map((c: any) => {
    const avgWaste = c.waste_rates.reduce((a: number, b: number) => a + b, 0) / c.waste_rates.length;
    const prevRates = prevWasteByCat[c.bread_category_id] || [];
    const prevAvg = prevRates.length > 0
      ? prevRates.reduce((a, b) => a + b, 0) / prevRates.length
      : null;

    let trend: 'improving' | 'stable' | 'worsening' = 'stable';
    if (prevAvg !== null) {
      if (avgWaste < prevAvg - 1) trend = 'improving';
      else if (avgWaste > prevAvg + 1) trend = 'worsening';
    }

    return {
      bread_category_id: c.bread_category_id,
      category_name: c.category_name,
      total_produced: c.total_produced,
      total_sold: c.total_sold,
      total_leftover: c.total_leftover,
      total_donated: c.total_donated,
      avg_waste_rate: Math.round(avgWaste * 100) / 100,
      prev_week_waste_rate: prevAvg !== null ? Math.round(prevAvg * 100) / 100 : null,
      trend,
      total_revenue: Math.round(c.total_revenue * 100) / 100,           // reporting-only
      total_ingredient_cost: Math.round(c.total_ingredient_cost * 100) / 100, // reporting-only
      total_gross_profit: Math.round(c.total_gross_profit * 100) / 100,        // reporting-only
    };
  });
}
```

---

## 6. Controllers (Controller Layer — thin HTTP handlers)

### 6.1 `src/controllers/inventoryController.ts` (fills Module 1 stub)

```typescript
import { Router } from 'express';
import { validateRequest } from '../middleware/validateRequest';
import { z } from 'zod';
import * as invService from '../services/inventoryService';

export const inventoryController = Router();

inventoryController.get('/inventory', async (req, res, next) => {
  try {
    const items = await invService.getInventory();
    res.json(items);
  } catch (err) { next(err); }
});

const RestockSchema = z.object({
  body: z.object({
    ingredient_id: z.string().uuid(),
    added_grams: z.number().positive(),
    expiry_date: z.string(),
    received_date: z.string().optional(),
    source: z.string().optional(),
    reason: z.string().optional().default('manual_restock'),
  }),
});

inventoryController.post('/inventory/restock', validateRequest(RestockSchema), async (req, res, next) => {
  try {
    const { ingredient_id, added_grams, expiry_date, received_date, source, reason } = req.body;
    await invService.restock(ingredient_id, added_grams, expiry_date, received_date, source, reason);
    res.json({ status: 'restocked', ingredient_id, added_grams });
  } catch (err) { next(err); }
});

const DeductSchema = z.object({
  body: z.object({
    category_id: z.string().uuid(),
    units_produced: z.number().int().positive(),
    production_date: z.string().optional(),
  }),
});

inventoryController.post('/inventory/deduct', validateRequest(DeductSchema), async (req, res, next) => {
  try {
    const { category_id, units_produced, production_date } = req.body;
    await invService.deductForProduction(category_id, units_produced, production_date);
    res.json({ status: 'deducted', category_id, units_produced });
  } catch (err) { next(err); }
});

inventoryController.get('/inventory/log', async (req, res, next) => {
  try {
    const filters: { reason?: string; dateFrom?: string } = {};
    if (typeof req.query.reason === 'string') filters.reason = req.query.reason;
    if (typeof req.query.dateFrom === 'string') filters.dateFrom = req.query.dateFrom;
    const log = await invService.getInventoryLog(filters);
    res.json(log);
  } catch (err) { next(err); }
});

inventoryController.get('/inventory/batches', async (req, res, next) => {
  try {
    const filters: { ingredientId?: string; status?: string; expiringBefore?: string } = {};
    if (typeof req.query.ingredientId === 'string') filters.ingredientId = req.query.ingredientId;
    if (typeof req.query.status === 'string') filters.status = req.query.status;
    if (typeof req.query.expiringBefore === 'string') filters.expiringBefore = req.query.expiringBefore;
    const batches = await invService.getBatches(filters);
    res.json(batches);
  } catch (err) { next(err); }
});

inventoryController.get('/inventory/expiring-soon', async (req, res, next) => {
  try {
    const days = typeof req.query.days === 'string' ? Number(req.query.days) : 7;
    const batches = await invService.getExpiringSoon(days);
    res.json(batches);
  } catch (err) { next(err); }
});

inventoryController.get('/inventory/quality', async (req, res, next) => {
  try {
    const asOfDate = typeof req.query.asOfDate === 'string' ? req.query.asOfDate : undefined;
    const report = await invService.getInventoryQuality(asOfDate);
    res.json(report);
  } catch (err) { next(err); }
});

inventoryController.post('/inventory/batches/:batchId/discard', async (req, res, next) => {
  try {
    await invService.discardBatch(req.params.batchId);
    res.json({ status: 'discarded', batch_id: req.params.batchId });
  } catch (err) { next(err); }
});

inventoryController.get('/inventory/low-stock', async (req, res, next) => {
  try {
    const items = await invService.getLowStockItems();
    res.json(items);
  } catch (err) { next(err); }
});
```

### 6.2 `src/controllers/recipeController.ts`

```typescript
import { Router } from 'express';
import { validateRequest } from '../middleware/validateRequest';
import { z } from 'zod';
import * as recipeService from '../services/recipeService';

export const recipeController = Router();

recipeController.get('/recipes', async (req, res, next) => {
  try {
    const recipes = await recipeService.getAllRecipes();
    res.json(recipes);
  } catch (err) { next(err); }
});

recipeController.get('/recipes/:categoryId', async (req, res, next) => {
  try {
    const recipe = await recipeService.getRecipe(req.params.categoryId);
    res.json(recipe);
  } catch (err) { next(err); }
});

const UpdateRecipeSchema = z.object({
  body: z.object({
    updates: z.array(z.object({
      ingredient_id: z.string().uuid(),
      grams_per_unit: z.number().positive(),
    })),
  }),
});

recipeController.put('/recipes/:categoryId', validateRequest(UpdateRecipeSchema), async (req, res, next) => {
  try {
    await recipeService.updateRecipe(req.params.categoryId, req.body.updates);
    res.json({ status: 'updated', categoryId: req.params.categoryId });
  } catch (err) { next(err); }
});
```

### 6.3 `src/controllers/recommendationController.ts`

```typescript
import { Router } from 'express';
import { generateRecommendation } from '../services/recommendationEngine';
import { saveProductionDecision, getProductionDecisions } from '../services/productionDecisionService';
import { validateRequest } from '../middleware/validateRequest';
import { z } from 'zod';

export const recommendationController = Router();

recommendationController.get('/recommendation/:date', async (req, res, next) => {
  try {
    const recommendation = await generateRecommendation(req.params.date);
    res.json(recommendation);
  } catch (err) { next(err); }
});

const ProductionDecisionSchema = z.object({
  body: z.object({
    target_date: z.string(),
    bread_category_id: z.string().uuid(),
    prediction_id: z.string().uuid().nullable().optional(),
    predicted_demand: z.number().int(),
    recommended_production: z.number().int(),
    max_producible: z.number().int().nonnegative(),
    final_selected_qty: z.number().int().nonnegative(),
    selected_option: z.enum(['full_prediction', 'reduced_due_constraint', 'manual_override']),
    decision_reason: z.string().nullable().optional(),
  }),
});

recommendationController.post('/production-decisions', validateRequest(ProductionDecisionSchema), async (req, res, next) => {
  try {
    const decision = await saveProductionDecision({
      ...req.body,
      confirmed_by: req.user.id,
    });
    res.json(decision);
  } catch (err) { next(err); }
});

recommendationController.get('/production-decisions/:date', async (req, res, next) => {
  try {
    const decisions = await getProductionDecisions(req.params.date);
    res.json(decisions);
  } catch (err) { next(err); }
});
```

### 6.4 `src/controllers/summaryController.ts`

```typescript
import { Router } from 'express';
import { getWeeklySummary } from '../services/weeklySummaryService';

export const summaryController = Router();

summaryController.get('/summary/weekly', async (req, res, next) => {
  try {
    const weekStart = (req.query.weekStart as string) || new Date().toISOString().split('T')[0];
    const summary = await getWeeklySummary(weekStart);
    res.json(summary);
  } catch (err) { next(err); }
});
```

### 6.5 Update `src/controllers/index.ts`

Add to the existing aggregator (from Module 1):

```typescript
import { inventoryController } from './inventoryController';
import { recipeController } from './recipeController';
import { recommendationController } from './recommendationController';
import { summaryController } from './summaryController';

// Replace the stub inventoryController with the real one
router.use(inventoryController);
router.use(recipeController);
router.use(recommendationController);
router.use(summaryController);
```

---

## 7. Request Flow — Smart Recommendation

```
Flutter: GET /api/recommendation/2026-06-27
  ↓
Node.js auth middleware (verify JWT)
  ↓
recommendationController handler (Controller)
  ↓
recommendationEngine.generateRecommendation('2026-06-27') (Service)
  ├─ Step 1: HTTP POST to ML_SERVER_URL/predict (Service → external)
  │   → { predictions: [{ Croissants: 120, confidence: 88 }, ...] }
  │
  ├─ Step 2: getInventoryMapForDate(targetDate) + getInventoryQuality() (Service → repos → Supabase)
  │   → aggregate stock snapshot, backed by FIFO inventory_batches
  │   → quality warnings for expired active batches, mismatches, missing recipe rows
  │
  ├─ Step 3: for each category:
  │   ├─ ingredientCalculator.calculateRequirements(category, 120, recipe)
  │   │   → recipeRepo.findByCategory() (Repo → Supabase)
  │   │   → [{ Flour: 9600 }, { Butter: 1800 }, { Yeast: 240 }, ...]
  │   ├─ constraintChecker.checkConstraints(requirements) (pure calc)
  │   │   → { constraints: [{ Yeast: have 200, need 240 }], max_producible: 100 }
  │   └─ if constraints:
  │       ├─ recommended_production = 100 (max_producible)
  │       └─ options = [
  │            { action: 'produce_reduced', qty: 100, note: 'May miss 20 sales' },
  │            { action: 'order_ingredients', order: [{ Yeast: 40g }], qty: 120, recommended: true }
  │          ]
  │
  ├─ Step 4: inventoryRepo.findLowStock() (Repo → Supabase)
  ├─ Step 5: getExpiringSoon(7) with severity labels
  └─ Step 6: return full recommendation
  ↓
Flutter receives: { date, categories: [...], low_stock_alerts: [...] }
```

After reviewing the recommendation, the manager confirms each category with `POST /api/production-decisions`. The service validates `final_selected_qty <= max_producible`, requires `decision_reason` for reduced/override decisions, stores `confirmed_by` from the authenticated user, writes `production_decision_confirmed` to `system_logs`, and does not deduct inventory.

---

## 8. Verification Plan

| Step | Command | Expected Result |
|---|---|---|
| 1 | `GET /api/inventory` (with JWT) | List of 5 ingredients with stock + low-stock flags |
| 2 | `POST /api/inventory/restock { ingredient_id, added_grams: 5000, expiry_date }` | Inventory snapshot increases, FIFO batch created, log entry created |
| 3 | `GET /api/inventory/batches?ingredientId=...` | Batches listed oldest expiry first |
| 4 | Create two yeast batches with different expiry dates, then `POST /api/inventory/deduct` | Older expiry batch is deducted first; `inventory_log.batch_id` records each movement |
| 5 | `GET /api/inventory/expiring-soon?days=7` | Active batches expiring soon are returned |
| 6 | `POST /api/inventory/batches/:batchId/discard` | Batch marked discarded, snapshot decreases, spoilage log created |
| 7 | `GET /api/inventory/expiring-soon?days=7` after setting expiry dates | Severity labels: today = critical, 1-3 days = warning, 4-7 days = info |
| 8 | `GET /api/inventory/quality` | Returns `ok`, `warning`, or `critical` with issue list |
| 9 | `GET /api/inventory/low-stock` | Returns ingredients below threshold |
| 10 | `GET /api/inventory/log?reason=daily_production` | Filtered log entries include batch IDs |
| 11 | `GET /api/recipes` | All 20 recipe rows (4 categories × 5 ingredients) |
| 12 | `GET /api/recipes/:categoryId` | Recipe for one category |
| 13 | `PUT /api/recipes/:categoryId { updates: [...] }` | Recipe updates in DB |
| 14 | `GET /api/recommendation/2026-06-27` | Full smart recommendation with constraints, expiring batches, quality report, and options |
| 15 | `POST /api/production-decisions { ... }` | Manager decision is stored/upserted with `confirmed_by`, `confirmed_at`, `max_producible`; reduced/override decisions require `decision_reason`; inventory quantity is unchanged |
| 16 | `GET /api/production-decisions/2026-06-27` | Returns all saved category decisions |
| 17 | Manually set yeast inventory to 200g, then GET recommendation | See "yeast shortage" scenario with 2 options (produce 100 + order 40g) |
| 18 | `GET /api/summary/weekly?weekStart=2026-06-23` | Per-category waste rates + trend (improving/stable/worsening) |
| 19 | Check `system_logs` table | Low-stock/expiry alert entries with severity 'warn' |
| 20 | `npm run typecheck` | No type errors |
| 21 | `npm run lint` | No lint errors |

---

## 9. Implementation Order

1. Add shared types to `backend/shared/types.ts` (schemas for inventory, recipes, recommendations, summaries)
2. Create `src/repositories/` (inventoryRepo, inventoryBatchRepo, inventoryLogRepo, productionDecisionRepo, recipeRepo, ingredientRepo, dailyResultRepo, donationRepo, breadCategoryRepo, predictionRepo)
3. Create `src/services/recipeService.ts` (recipe business logic, calls recipeRepo)
4. Create `src/services/ingredientCalculator.ts` (requirements + max_producible, pure calc)
5. Create `src/services/constraintChecker.ts` (detect shortages, pure calc)
6. Create `src/services/fifoBatchService.ts` (FIFO batch creation, oldest-batch deduction, discard)
7. Create `src/services/inventoryQualityService.ts` (expired active batches, snapshot mismatch, missing recipes)
8. Create `src/services/inventoryService.ts` (restock, deduct, low-stock/expiry/quality, calls repos)
9. Create `src/services/productionDecisionService.ts` (confirm manager decision + feasibility/reason validation + audit log)
10. Create `src/services/recommendationEngine.ts` (signature feature, reads stored prediction through Repos only)
11. Create `src/services/weeklySummaryService.ts` (calls repos; aggregates revenue/ingredient_cost/gross_profit cached on daily_results — reporting-only)
11b. Create `src/services/ingredientCostCalculator.ts` (reporting-only — costPerUnit/costForProduction; NEVER imported by recommendationEngine/constraintChecker)
12. Create `src/controllers/inventoryController.ts` (replaces Module 1 stub, calls inventoryService)
13. Create `src/controllers/recipeController.ts` (calls recipeService)
14. Create `src/controllers/recommendationController.ts` (calls recommendationEngine + productionDecisionService)
15. Create `src/controllers/summaryController.ts` (calls weeklySummaryService)
16. Update `src/controllers/index.ts` to register new controllers
17. Verify: run all 21 verification steps

---

## 10. Open Items for Implementation

| # | Item | Notes |
|---|---|---|
| 1 | `get_low_stock_items` RPC | Need to create a Supabase function/stored proc OR inline the query in inventoryService. Inline is simpler. |
| 2 | Recipe update atomicity | Current `updateRecipe` loops updates individually; wrap in a Supabase transaction or use `.upsert()` for atomicity |
| 3 | Concurrent FIFO deduction race | If two deductions happen simultaneously, snapshot or batch rows could go negative. Add DB checks plus a transaction/RPC for production deduction if time allows. |
| 4 | Missing stored prediction | Return a validation error directing the manager to generate the prediction through `PredictionOrchestrationService`; RecommendationEngine never calls FastAPI |
| 5 | Recommendation caching | The same recommendation may be requested multiple times in a morning; consider caching for 1 hour |
| 6 | Exact re-simulation reversal | MVP restores ingredients as correction batches. A production-grade version would reverse exact `inventory_log.batch_id` movements by production run ID. |

---

**Plan Status:** Complete. Ready for implementation on your signal.
