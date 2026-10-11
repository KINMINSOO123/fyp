# Module 4: POS Simulation — Detailed Plan

**Build Order:** 5th (depends on Module 0, Module 1, Module 2, Module 3)
**Status:** Detailed plan — ready for implementation
**Architecture:** View → `PosSimulationController` → `PosSimulationService` → Services/Repos (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan (sub-modules, simulation flow, stock-out example, file structure).
> This README documents the concrete artifacts to build: repo methods, service function signatures, controller code, verification.

## Revision baseline (authoritative)

- Use the stored `DailyPrediction.predictedUnitsSold` as the simulation baseline. Weather, holiday, season and other context already included in that prediction must not be multiplied again; context retrieval is for traceability/display.
- Validate confirmed production and valid inventory first. Deduct FIFO exactly once before simulated sales, identify the movements, and roll back or reverse them if any later processing fails.
- `DailyResult` is the detailed completed simulation outcome and uses `unitsSold`, `lostSales`, `estimatedDemand`, `leftover` and `remainingUnallocatedLeftover`.
- After successful completion, create one validated `DailySalesRecord` per category with `dataOrigin = SIMULATION_GENERATED`. Development training may use it; evaluation must be labelled simulation-based.
- Use class names `PosSimulationController`, `PosSimulationService` and `TransactionRecordingService`. Express routers remain thin modules.

All older double-context multiplier, direct `daily_results` training, deduction-after-sales, retry-without-reversal, `salesController`, `simulationService`, `predicted_demand`, `sold` or `demand` sketches below are superseded and must be adapted before implementation.

---

## 1. Dependencies (from Modules 0, 1, 3)

| Artifact | Used For |
|---|---|
| Module 0 schema: `sales_transactions`, `production_decisions`, `daily_production`, detailed `daily_results`, validated `daily_sales_records`, `daily_predictions`, `bread_categories` | CRUD + business logic through TypeScript Repos |
| Module 0 `shared/types.ts` | Zod schemas for request/response validation (Model layer) |
| Module 1 `ContextService.getContext(date)` | Fetch weather + calendar for traceability/display only |
| Module 1 `DailyPredictionRepo.findByDate(date)` | Read the stored prediction baseline |
| Module 1 `breadCategoryRepo.findAll()` | Read `selling_price` per category — used to snapshot `sales_transactions.unit_price` at sale time. **Reporting only** — not used to alter production. |
| Module 1 `repositories/baseRepo.ts` | Base class new repos extend |
| Module 3 `InventoryService.deductFifo` | Deduct ingredients from valid FIFO batches exactly once before simulated sales |
| Module 3 `InventoryService.reverseDeduction` | Reverse linked deduction if later processing fails or an authorised replacement occurs |
| Module 3 `ingredientCostCalculator.costPerUnit(categoryId)` | Compute ingredient cost per produced unit (reporting-only) → drives `daily_results.ingredient_cost` (on PRODUCED). Not used for any optimisation. |
| Module 3 `productionDecisionService.getProductionDecisions` | Use manager-selected quantities when available |
| Module 0 configurable settings | Time-slot/stochastic controls; context multipliers are not reapplied |
| Module 1 `notificationService.emit` | Emit `stock_out` alert when `lost_sales > 0` during simulation (live bell badge + FCM background push) |

---

## 2. Artifacts to Build

> Layered per `../ARCHITECTURE.md`. Repos = Supabase only. Services = business logic + call repos. Controllers = thin HTTP handlers.

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `backend/src/repositories/salesTransactionRepo.ts` | Repo | sales_transactions CRUD + findByDate + findBySlot + deleteByDate |
| 2 | `backend/src/repositories/dailyProductionRepo.ts` | Repo | daily_production CRUD + findByDate + deleteByDate |
| 3 | `backend/src/repositories/dailyResultRepo.ts` | Repo | EXTEND Module 3's repo: add insert + findByDate + deleteByDate |
| 4 | `backend/src/services/salesDistributionService.ts` | Service | Apply time-slot weights (pure calc, no DB) |
| 5 | `backend/src/services/posSimulationService.ts` | Service | Stored-prediction baseline, stochastic/time-slot simulation and stock-out logic |
| 6 | `backend/src/services/transactionRecordingService.ts` | Service | FIFO-before-sales unit of work, operational writes, history creation and failure reversal |
| 7 | `backend/src/services/manualCorrectionService.ts` | Service | Correct daily_results values + notes, recalculate derived metrics, log correction |
| 8 | `backend/src/controllers/posSimulationController.ts` | Controller | Class-based POS simulation endpoints |
| 9 | `backend/src/routes/posSimulationRoutes.ts` | Module | Thin Express route registration |
| 10 | Update `backend/shared/types.ts` | Model | Add canonical `DailyProduction`, `SalesTransaction`, `DailyResult`, `DailySalesRecord`, `DataOrigin`, request and summary schemas |
| 10a | `backend/src/repositories/dailySalesRecordRepo.ts` | Repo | Insert validated `SIMULATION_GENERATED` history after success |
| 11 | (uses) `backend/src/services/notificationService.ts` | Service | Built in **Module 1** — this module imports and calls it for `stock_out` alerts. Not re-created here. |

---

## 3. Shared Types (add to `backend/shared/types.ts`)

```typescript
// Sales transaction (raw — every simulated sale)
export const SalesTransactionSchema = z.object({
  id: z.string().uuid().optional(),
  sale_date: z.string(),
  sale_time: z.string(),
  time_slot: z.enum(['morning', 'afternoon', 'evening']),
  bread_category_id: z.string().uuid(),
  quantity: z.number().int().positive(),
  unit_price: z.number().nonnegative(),   // snapshot of bread_categories.selling_price at sale moment (RM). Reporting only.
  subtotal:   z.number().nonnegative(),    // quantity * unit_price (RM)
  created_at: z.string().optional(),
});
export type SalesTransaction = z.infer<typeof SalesTransactionSchema>;

// Daily production record
export const DailyProductionSchema = z.object({
  id: z.string().uuid().optional(),
  production_date: z.string(),
  bread_category_id: z.string().uuid(),
  production_decision_id: z.string().uuid().nullable().optional(),
  recommended_qty: z.number().int(),
  actual_produced: z.number().int(),
  adjustment_reason: z.string().nullable().optional(),
});
export type DailyProduction = z.infer<typeof DailyProductionSchema>;

// Daily results (EXTEND existing schema with demand + lost_sales + notes)
export const DailyResultSchema = z.object({
  id: z.string().uuid().optional(),
  result_date: z.string(),
  bread_category_id: z.string().uuid(),
  prediction_id: z.string().uuid().nullable().optional(),
  predicted: z.number().int(),
  produced: z.number().int(),
  sold: z.number().int(),
  leftover: z.number().int(),
  demand: z.number().int(),              // NEW — simulated demand before capping
  lost_sales: z.number().int().default(0), // NEW — stock-out tracking
  waste_rate_pct: z.number().nullable().optional(),
  error_units: z.number().int().nullable().optional(),
  error_pct: z.number().nullable().optional(),
  notes: z.string().nullable().optional(),
  revenue: z.number().nonnegative().default(0),          // NEW — SUM(sales_transactions.subtotal) for this category-day. Cache for dashboards. Reporting only.
  ingredient_cost: z.number().nonnegative().default(0),  // NEW — produced * costPerUnit(category). Cost on PRODUCED, not sold. Reporting only.
  gross_profit: z.number().default(0),                   // NEW — revenue - ingredient_cost. Proves "less waste = better profit".
});
export type DailyResult = z.infer<typeof DailyResultSchema>;

// Simulation request
export const SimulateRequestSchema = z.object({
  date: z.string(),
  producedOverride: z.record(z.string().uuid(), z.number().int().positive()).optional(),
  dryRun: z.boolean().optional().default(false),
  forceRefresh: z.boolean().optional().default(false),
});
export type SimulateRequest = z.infer<typeof SimulateRequestSchema>;

// Simulation result summary
export const SimulationSummarySchema = z.object({
  date: z.string(),
  categories: z.array(z.object({
    bread_category_id: z.string().uuid(),
    category_name: z.string(),
    predicted: z.number().int(),
    produced: z.number().int(),
    demand: z.number().int(),
    sold: z.number().int(),
    leftover: z.number().int(),
    lost_sales: z.number().int(),
    waste_rate_pct: z.number(),
    // Reporting-only financial snapshot for this category-day (cached on daily_results)
    revenue: z.number().nonnegative(),
    ingredient_cost: z.number().nonnegative(),  // cost on PRODUCED, not sold
    gross_profit: z.number(),
  })),
  total_sold: z.number().int(),
  total_leftover: z.number().int(),
  total_lost_sales: z.number().int(),
  total_revenue: z.number().nonnegative(),
  total_ingredient_cost: z.number().nonnegative(),
  total_gross_profit: z.number(),
  weather_condition: z.string(),
  holiday_multiplier: z.number(),
  dry_run: z.boolean().optional().default(false),
});
export type SimulationSummary = z.infer<typeof SimulationSummarySchema>;
```

---

## 4. Repositories (Repo Layer — Supabase only)

> Repos do ONLY Supabase queries. No business logic. See `../ARCHITECTURE.md` §4.2. All extend `baseRepo.ts` from Module 1.

### 4.1 `src/repositories/salesTransactionRepo.ts`

```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { SalesTransaction } from '../../shared/types';

export class SalesTransactionRepo extends BaseRepo<SalesTransaction> {
  constructor() { super('sales_transactions'); }

  async findByDate(saleDate: string): Promise<SalesTransaction[]> {
    const { data, error } = await supabase
      .from('sales_transactions')
      .select('*')
      .eq('sale_date', saleDate)
      .order('sale_time');
    if (error) throw error;
    return data;
  }

  async findByDateAndSlot(saleDate: string, slot: string): Promise<SalesTransaction[]> {
    const { data, error } = await supabase
      .from('sales_transactions')
      .select('*')
      .eq('sale_date', saleDate)
      .eq('time_slot', slot)
      .order('sale_time');
    if (error) throw error;
    return data;
  }

  async findByDateAndCategory(saleDate: string, categoryId: string): Promise<SalesTransaction[]> {
    const { data, error } = await supabase
      .from('sales_transactions')
      .select('*')
      .eq('sale_date', saleDate)
      .eq('bread_category_id', categoryId)
      .order('sale_time');
    if (error) throw error;
    return data;
  }

  async deleteByDate(saleDate: string): Promise<void> {
    const { error } = await supabase
      .from('sales_transactions')
      .delete()
      .eq('sale_date', saleDate);
    if (error) throw error;
  }

  async insertMany(transactions: SalesTransaction[]): Promise<void> {
    if (transactions.length === 0) return;
    const { error } = await supabase
      .from('sales_transactions')
      .insert(transactions);
    if (error) throw error;
  }
}
export const salesTransactionRepo = new SalesTransactionRepo();
```

### 4.2 `src/repositories/dailyProductionRepo.ts`

```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { DailyProduction } from '../../shared/types';

export class DailyProductionRepo extends BaseRepo<DailyProduction> {
  constructor() { super('daily_production'); }

  async findByDate(productionDate: string): Promise<DailyProduction[]> {
    const { data, error } = await supabase
      .from('daily_production')
      .select('*')
      .eq('production_date', productionDate);
    if (error) throw error;
    return data;
  }

  async deleteByDate(productionDate: string): Promise<void> {
    const { error } = await supabase
      .from('daily_production')
      .delete()
      .eq('production_date', productionDate);
    if (error) throw error;
  }

  async upsert(data: DailyProduction): Promise<void> {
    const { error } = await supabase
      .from('daily_production')
      .upsert(data, { onConflict: 'production_date,bread_category_id' });
    if (error) throw error;
  }
}
export const dailyProductionRepo = new DailyProductionRepo();
```

### 4.3 `src/repositories/dailyResultRepo.ts` (EXTEND Module 3's repo)

> Module 3 already defined `findByDateRange` (read, for weekly summary). Module 4 adds write + delete methods for simulation.

```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { DailyResult } from '../../shared/types';

export class DailyResultRepo extends BaseRepo<DailyResult> {
  constructor() { super('daily_results'); }

  // === From Module 3 (weekly summary) ===
  async findByDateRange(startDate: string, endDate: string): Promise<any[]> {
    const { data, error } = await supabase
      .from('daily_results')
      .select('bread_category_id, produced, sold, leftover, waste_rate_pct, bread_categories(name)')
      .gte('result_date', startDate)
      .lte('result_date', endDate);
    if (error) throw error;
    return data;
  }

  // === NEW in Module 4 (simulation) ===
  async findByDate(resultDate: string): Promise<DailyResult[]> {
    const { data, error } = await supabase
      .from('daily_results')
      .select('*')
      .eq('result_date', resultDate);
    if (error) throw error;
    return data;
  }

  async deleteByDate(resultDate: string): Promise<void> {
    const { error } = await supabase
      .from('daily_results')
      .delete()
      .eq('result_date', resultDate);
    if (error) throw error;
  }

  async upsert(data: DailyResult): Promise<void> {
    const { error } = await supabase
      .from('daily_results')
      .upsert(data, { onConflict: 'result_date,bread_category_id' });
    if (error) throw error;
  }
}
export const dailyResultRepo = new DailyResultRepo();
```

---

## 5. Services (Service Layer — business logic, calls repos)

> Services contain business logic. They call repos for DB access. No direct Supabase calls. See `../ARCHITECTURE.md` §4.3.

### 5.1 `src/services/salesDistributionService.ts` (pure calc — no DB)

```typescript
interface SlotAllocation {
  morning: number;
  afternoon: number;
  evening: number;
}

interface SlotWeights {
  morning: number;
  afternoon: number;
  evening: number;
}

function gaussianNoise(sigmaPct: number): number {
  // Box-Muller transform for gaussian noise
  // Returns multiplier centered at 1.0 with given standard deviation
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return 1 + (z * sigmaPct);
}

export function distributeSold(sold: number, weights: SlotWeights): SlotAllocation {
  """Apply time-slot weights + gaussian noise (±10%) per slot.
  Ensures slot totals add up to sold (remainder goes to evening)."""
  const morning = Math.max(0, Math.round(sold * weights.morning * gaussianNoise(0.10)));
  const afternoon = Math.max(0, Math.round(sold * weights.afternoon * gaussianNoise(0.10)));
  const evening = Math.max(0, sold - morning - afternoon);  // remainder ensures total = sold
  return { morning, afternoon, evening };
}

export function randomTimeInSlot(slot: string): string {
  """Generate a random time within the slot's time range."""
  const ranges = {
    morning: { start: 6 * 60, end: 11 * 60 },     // 06:00 - 11:00
    afternoon: { start: 11 * 60, end: 15 * 60 },  // 11:00 - 15:00
    evening: { start: 15 * 60, end: 18 * 60 },    // 15:00 - 18:00
  };
  const range = ranges[slot];
  const minutes = range.start + Math.floor(Math.random() * (range.end - range.start));
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}`;
}

export function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
```

### 5.2 Historical `transactionRecordingService.ts` sketch (ordering superseded)

> Do not implement the write-then-deduct ordering shown below. The canonical sequence is validate → FIFO deduction exactly once → simulated sales/result writes → validated `DailySalesRecord(SIMULATION_GENERATED)` → commit. Any later failure rolls back or calls `InventoryService.reverseDeduction(reference)`.

```typescript
import { salesTransactionRepo } from '../repositories/salesTransactionRepo';
import { dailyProductionRepo } from '../repositories/dailyProductionRepo';
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { inventoryService } from './inventoryService';
import { ingredientCostCalculator } from './ingredientCostCalculator';  // Module 3 — reporting-only
import { logger } from '../utils/logger';
import { SalesTransaction, DailyProduction, DailyResult } from '../../shared/types';

interface DayData {
  date: string;
  category: {
    bread_category_id: string;
    category_name: string;
    predicted_demand: number;
    id?: string;
  };
  produced: number;
  sold: number;
  demand: number;
  leftover: number;
  lostSales: number;
  wasteRate: number;
  transactions: SalesTransaction[];   // each row already carries unit_price + subtotal (set in simulationService.generateTransactions)
  predictionId?: string;
  productionDecisionId?: string;
}

export const transactionRecordingService = {
  async recordDay(data: DayData): Promise<void> {
    // 1. Insert sales_transactions (bulk)
    await salesTransactionRepo.insertMany(data.transactions);

    // 2. Insert daily_production, linked to production_decision_id when available
    await dailyProductionRepo.upsert({
      production_date: data.date,
      bread_category_id: data.category.bread_category_id,
      production_decision_id: data.productionDecisionId ?? null,
      recommended_qty: data.category.predicted_demand,
      actual_produced: data.produced,
    } as DailyProduction);

    // 3. Insert daily_results (with demand + lost_sales + financial cache)
    const errorUnits = Math.abs(data.category.predicted_demand - data.sold);
    const errorPct = data.sold > 0
      ? (errorUnits / data.sold) * 100
      : 0;

    // Financial snapshot (reporting-only). Cost is on PRODUCED units (sold + leftover),
    // so wasted/donated bread's ingredient cost still counts — making waste visibly eat profit.
    const revenue         = data.transactions.reduce((s, t) => s + (t.subtotal ?? 0), 0);
    const costPerUnit     = await ingredientCostCalculator.costPerUnit(data.category.bread_category_id);
    const ingredient_cost = data.produced * costPerUnit;   // produced, NOT sold — by design
    const gross_profit    = revenue - ingredient_cost;

    await dailyResultRepo.upsert({
      result_date: data.date,
      bread_category_id: data.category.bread_category_id,
      prediction_id: data.predictionId ?? null,
      predicted: data.category.predicted_demand,
      produced: data.produced,
      sold: data.sold,
      leftover: data.leftover,
      demand: data.demand,
      lost_sales: data.lostSales,
      waste_rate_pct: data.wasteRate,
      error_units: errorUnits,
      error_pct: errorPct,
      revenue,
      ingredient_cost,
      gross_profit,
    } as DailyResult);

    // 4. Deduct ingredients using FIFO batches (call Module 3 service)
    await inventoryService.deductForProduction(
      data.category.bread_category_id,
      data.produced,
      data.date
    );

    logger.info('Day recorded', {
      date: data.date,
      category: data.category.category_name,
      produced: data.produced,
      sold: data.sold,
      demand: data.demand,
      lostSales: data.lostSales,
    });
  },

  async clearDateData(date: string): Promise<void> {
    """For re-simulation: reverse inventory + delete all data for the date."""
    // 1. Read existing daily_production for date
    const existing = await dailyProductionRepo.findByDate(date);

    // 2. Reverse inventory deductions (add back ingredients)
    for (const prod of existing) {
      await inventoryService.reverseProductionDeduction(
        prod.bread_category_id,
        prod.actual_produced,
        date
      );
    }

    // 3. Delete all data for this date
    await salesTransactionRepo.deleteByDate(date);
    await dailyProductionRepo.deleteByDate(date);
    await dailyResultRepo.deleteByDate(date);

    logger.info('Date data cleared for re-simulation', { date, categoriesReversed: existing.length });
  },
};
```

### 5.3 Historical `simulationService.ts` sketch (superseded by `PosSimulationService`)

> Do not implement the weather/holiday multiplication shown below. Use the stored `DailyPrediction` baseline plus configured stochastic/time-slot variation only.

```typescript
import { predictionRepo } from '../repositories/predictionRepo';
import { fetchContext } from './contextService';
import { salesDistributionService } from './salesDistributionService';
import { transactionRecordingService } from './transactionRecordingService';
import { notificationService } from './notificationService';
import { getProductionDecisions } from './productionDecisionService';
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { loadConstants } from '../features/constants';
import { logger } from '../utils/logger';
import { SalesTransaction, SimulationSummary } from '../../shared/types';

interface SimulateOptions {
  producedOverride?: Record<string, number>;
  dryRun?: boolean;
  forceRefresh?: boolean;
}

function gaussianNoise(sigmaPct: number): number {
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return 1 + (z * sigmaPct);
}

function generateTransactions(
  date: string,
  categoryId: string,
  slotAlloc: { morning: number; afternoon: number; evening: number },
  sellingPrice: number    // snapshot of bread_categories.selling_price for this category (reporting-only)
): SalesTransaction[] {
  const transactions: SalesTransaction[] = [];
  for (const [slot, units] of Object.entries(slotAlloc)) {
    let remaining = units;
    while (remaining > 0) {
      const qty = Math.min(salesDistributionService.randomInt(1, 3), remaining);
      const saleTime = salesDistributionService.randomTimeInSlot(slot);
      transactions.push({
        sale_date: date,
        sale_time: saleTime,
        time_slot: slot as 'morning' | 'afternoon' | 'evening',
        bread_category_id: categoryId,
        quantity: qty,
        unit_price: sellingPrice,                  // snapshot at sale moment
        subtotal: qty * sellingPrice,               // quantity * unit_price
      });
      remaining -= qty;
    }
  }
  return transactions;
}

export const simulationService = {
  async simulateDay(date: string, options: SimulateOptions = {}): Promise<SimulationSummary> {
    const constants = loadConstants();

    // STEP 0: Handle re-simulation
    if (options.forceRefresh && !options.dryRun) {
      const existing = await dailyResultRepo.findByDate(date);
      if (existing.length > 0) {
        logger.info('Re-simulating date (forceRefresh)', { date });
        await transactionRecordingService.clearDateData(date);
      }
    }

    // STEP 1: Fetch prediction for date
    const predictions = await predictionRepo.findByDate(date);
    if (predictions.length === 0) {
      throw new Error(`No predictions found for date ${date}. Run prediction first.`);
    }

    const decisions = await getProductionDecisions(date);
    const decisionByCategory = new Map(
      decisions.map(d => [d.bread_category_id, d])
    );

    // STEP 2: Fetch context (weather + calendar) + bread categories (for price snapshot)
    const context = await fetchContext(date);
    const weatherCondition = context.weather?.condition ?? 'cloudy';
    const weatherMult = constants.weather_multipliers[weatherCondition] ?? 1.0;
    const holidayMult = context.calendar[0]?.demand_multiplier ?? 1.0;

    // Fetch bread categories once — used purely to snapshot selling_price into sales_transactions.unit_price.
    // Reporting-only: prices do NOT affect demand, production, or stock-out logic below.
    const categoryRows = await breadCategoryRepo.findAll();
    const sellingPriceByCat: Record<string, number> = {};
    for (const c of categoryRows) sellingPriceByCat[c.id] = c.selling_price ?? 0;

    logger.info('Simulation context', {
      date, weatherCondition, weatherMult, holidayMult,
      predictionCount: predictions.length,
    });

    // STEP 3: Process each category
    const slotWeights = {
      morning: constants.time_slots.find(s => s.slot === 'morning')!.weight_pct / 100,
      afternoon: constants.time_slots.find(s => s.slot === 'afternoon')!.weight_pct / 100,
      evening: constants.time_slots.find(s => s.slot === 'evening')!.weight_pct / 100,
    };

    const categories = [];
    let totalSold = 0;
    let totalLeftover = 0;
    let totalLostSales = 0;
    let totalRevenue = 0;          // reporting-only
    let totalIngredientCost = 0;   // reporting-only
    let totalGrossProfit = 0;      // reporting-only

    for (const pred of predictions) {
      // 3a. Determine production qty.
      // Normal path: use the manager-confirmed production decision.
      // producedOverride is for testing/manual simulation scenarios only.
      const decision = decisionByCategory.get(pred.bread_category_id);
      const produced = options.producedOverride?.[pred.bread_category_id]
        ?? decision?.final_selected_qty
        ?? pred.predicted_demand;

      // 3b. Calculate simulated demand
      const base = pred.predicted_demand;
      const demand = Math.max(0, Math.round(base * weatherMult * holidayMult * gaussianNoise(0.10)));

      // 3c. Apply stock-out logic
      const sold = Math.min(demand, produced);
      const leftover = produced - sold;
      const lostSales = Math.max(0, demand - produced);
      const wasteRate = produced > 0 ? (leftover / produced) * 100 : 0;

      // 3c'. Stock-out notification (Module 1 notificationService)
      // Emits a 'stock_out' alert → Supabase Realtime (foreground) + FCM (background push).
      // Dedupe guard in notificationService skips if unread alert with same related_id exists.
      if (lostSales > 0) {
        await notificationService.emit({
          type: 'stock_out',
          severity: 'warning',
          title: `Stock-Out: ${pred.category_name ?? 'Bread'}`,
          message: `${lostSales} lost sales on ${date} (demand ${demand} exceeded production ${produced}).`,
          relatedId: pred.bread_category_id,
        });
      }

      // 3d. Distribute sold across 3 time slots
      const slotAlloc = salesDistributionService.distributeSold(sold, slotWeights);

      // 3e. Generate transactions per slot
      const transactions = generateTransactions(
        date,
        pred.bread_category_id,
        slotAlloc,
        sellingPriceByCat[pred.bread_category_id] ?? 0, // snapshot for sales_transactions.unit_price
      );

      // 3f + 3g + 3h. Record production + results + transactions + deduct inventory.
      // Historical dry-run reruns return a summary only; they must not rewrite sales,
      // daily_results, or current FIFO inventory.
      if (!options.dryRun) {
        await transactionRecordingService.recordDay({
          date,
          category: {
            bread_category_id: pred.bread_category_id,
            category_name: pred.category_name ?? pred.bread_categories?.name ?? 'Unknown',
            predicted_demand: pred.predicted_demand,
            id: pred.id,
          },
          produced,
          sold,
          demand,
          leftover,
          lostSales,
          wasteRate,
          transactions,
          predictionId: pred.id,
        });
      }

      // Financial snapshot (reporting-only) — matches what transactionRecordingService caches on daily_results
      const catRevenue = transactions.reduce((s, t) => s + (t.subtotal ?? 0), 0);
      const catCostPerUnit = await ingredientCostCalculator.costPerUnit(pred.bread_category_id);
      const catIngredientCost = produced * catCostPerUnit;  // PRODUCED, not sold — by design
      const catGrossProfit = catRevenue - catIngredientCost;

      categories.push({
        bread_category_id: pred.bread_category_id,
        category_name: pred.category_name ?? 'Unknown',
        predicted: pred.predicted_demand,
        produced,
        demand,
        sold,
        leftover,
        lost_sales: lostSales,
        waste_rate_pct: Math.round(wasteRate * 100) / 100,
        revenue: catRevenue,
        ingredient_cost: catIngredientCost,
        gross_profit: catGrossProfit,
      });

      totalSold += sold;
      totalLeftover += leftover;
      totalLostSales += lostSales;
      totalRevenue += catRevenue;
      totalIngredientCost += catIngredientCost;
      totalGrossProfit += catGrossProfit;
    }

    logger.info('Simulation complete', {
      date, categories: categories.length, totalSold, totalLeftover, totalLostSales,
      totalRevenue, totalIngredientCost, totalGrossProfit,
    });

    return {
      date,
      categories,
      total_sold: totalSold,
      total_leftover: totalLeftover,
      total_lost_sales: totalLostSales,
      total_revenue: totalRevenue,                  // reporting-only
      total_ingredient_cost: totalIngredientCost,   // reporting-only
      total_gross_profit: totalGrossProfit,         // reporting-only
      weather_condition: weatherCondition,
      holiday_multiplier: holidayMult,
      dry_run: options.dryRun ?? false,
    };
  },
};
```

---

## 6. Historical Router-as-Controller Sketch (superseded)

The final design uses a `PosSimulationController` class and a separate thin Express router module. The following `salesController = Router()` example is retained only as historical planning context.

### `src/controllers/salesController.ts` (fills Module 1 stub)

```typescript
import { Router } from 'express';
import { validateRequest } from '../middleware/validateRequest';
import { z } from 'zod';
import { simulationService } from '../services/simulationService';
import { manualCorrectionService } from '../services/manualCorrectionService';
import { salesTransactionRepo } from '../repositories/salesTransactionRepo';
import { dailyResultRepo } from '../repositories/dailyResultRepo';

export const salesController = Router();

const SimulateSchema = z.object({
  body: z.object({
    date: z.string(),
    producedOverride: z.record(z.string().uuid(), z.number().int().positive()).optional(),
    dryRun: z.boolean().optional().default(false),
    forceRefresh: z.boolean().optional().default(false),
  }),
});

salesController.post('/sales/simulate', validateRequest(SimulateSchema), async (req, res, next) => {
  try {
    const { date, producedOverride, dryRun, forceRefresh } = req.body;
    const result = await simulationService.simulateDay(date, { producedOverride, dryRun, forceRefresh });
    res.json(result);
  } catch (err) { next(err); }
});

salesController.get('/sales/:date', async (req, res, next) => {
  try {
    const transactions = await salesTransactionRepo.findByDate(req.params.date);
    res.json(transactions);
  } catch (err) { next(err); }
});

salesController.get('/sales/:date/summary', async (req, res, next) => {
  try {
    const results = await dailyResultRepo.findByDate(req.params.date);
    res.json(results);
  } catch (err) { next(err); }
});

const CorrectionSchema = z.object({
  body: z.object({
    produced: z.number().int().nonnegative().optional(),
    sold: z.number().int().nonnegative().optional(),
    demand: z.number().int().nonnegative().optional(),
    lost_sales: z.number().int().nonnegative().optional(),
    notes: z.string().optional(),
  }),
});

salesController.patch('/sales/:date/summary/:categoryId', validateRequest(CorrectionSchema), async (req, res, next) => {
  try {
    const result = await manualCorrectionService.correctDailyResult(
      req.params.date,
      req.params.categoryId,
      req.body
    );
    res.json(result);
  } catch (err) { next(err); }
});

salesController.get('/sales/:date/slot/:slot', async (req, res, next) => {
  try {
    const transactions = await salesTransactionRepo.findByDateAndSlot(
      req.params.date, req.params.slot
    );
    res.json(transactions);
  } catch (err) { next(err); }
});

salesController.get('/sales/:date/category/:categoryId', async (req, res, next) => {
  try {
    const transactions = await salesTransactionRepo.findByDateAndCategory(
      req.params.date, req.params.categoryId
    );
    res.json(transactions);
  } catch (err) { next(err); }
});
```

### Update `src/controllers/index.ts`

Replace the stub import with the real controller:

```typescript
import { salesController } from './salesController';
// ... other imports ...
router.use(salesController);
```

---

## 7. Canonical Request Flow — Simulation

```text
PosSimulationController
  -> PosSimulationService
     1. Load confirmed ProductionDecision and stored DailyPrediction.
     2. Retrieve context only for traceability/display.
     3. Validate all confirmed quantities and valid inventory.
     4. TransactionRecordingService deducts FIFO once using an idempotency reference.
     5. Generate stochastic/time-slot sales from the stored prediction baseline.
     6. Persist DailyProduction, SalesTransaction and detailed DailyResult.
     7. Persist validated DailySalesRecord(unitsSold, SIMULATION_GENERATED).
     8. Commit and return summary.
     On failure after step 4: roll back/reverse the linked deduction and create no completed history.
```

### Historical flow sketch (double-context and deduction ordering superseded)

```
Flutter manager action: POST /api/sales/simulate
  Body: { date: "2026-06-26", dryRun: false, forceRefresh: false }
  ↓
Node.js auth middleware (verify JWT)
  ↓
salesController handler (Controller)
  ↓
simulationService.simulateDay('2026-06-26', { dryRun: false, forceRefresh: false }) (Service)
  ├─ STEP 0: if forceRefresh → transactionRecordingService.clearDateData()
  │   ├─ dailyProductionRepo.findByDate() (Repo → Supabase)
  │   ├─ inventoryService.reverseProductionDeduction() (Service → FIFO correction batches)
  │   ├─ salesTransactionRepo.deleteByDate() (Repo → Supabase)
  │   ├─ dailyProductionRepo.deleteByDate() (Repo → Supabase)
  │   └─ dailyResultRepo.deleteByDate() (Repo → Supabase)
  │
  ├─ STEP 1: predictionRepo.findByDate('2026-06-26') (Repo → Supabase)
  │   → [{ bread_category_id, predicted_demand, confidence, ... }]
  │
  ├─ STEP 2: contextService.fetchContext('2026-06-26') (Service)
  │   ├─ weatherService.getWeather() → weatherRepo (Repo → Supabase)
  │   └─ calendarService.getHolidays() → calendarRepo (Repo → Supabase)
  │   → { weather: { condition: 'rainy' }, calendar: [{ demand_multiplier: 1.30 }] }
  │
  ├─ STEP 3: for each category (4 total):
  │   ├─ Calculate demand = predicted × 0.85 (rainy) × 1.30 (holiday) × noise
  │   ├─ Cap sold at produced, compute lost_sales
  │   ├─ salesDistributionService.distributeSold() (pure calc)
  │   ├─ generateTransactions() (pure calc)
  │   ├─ IF lost_sales > 0:
  │   │   └─ notificationService.emit({type:'stock_out', severity:'warning', relatedId:catId})
  │   │       → writes notifications row → Supabase Realtime INSERT → Flutter bell badge
  │   │       → pushService.broadcast → FCM → staff phone lock-screen (if app backgrounded)
  │   │       (dedupe guard skips if unread 'stock_out' for same catId already exists)
  │   └─ transactionRecordingService.recordDay() (Service)
  │       ├─ salesTransactionRepo.insertMany() (Repo → Supabase)
  │       ├─ dailyProductionRepo.upsert() (Repo → Supabase)
  │       ├─ dailyResultRepo.upsert() (Repo → Supabase)
  │       └─ inventoryService.deductForProduction() (Service → FIFO batches + inventory snapshot)
  │
  └─ STEP 4: return summary
  ↓
Flutter receives: { date, categories: [...with revenue/ingredient_cost/gross_profit per cat], total_sold, total_leftover, total_lost_sales, total_revenue, total_ingredient_cost, total_gross_profit }
```

For historical as-of reruns, call the same endpoint with `dryRun: true`. The service still reads the selected date's prediction and context, but skips `clearDateData()` and `recordDay()`, so it does not delete/insert sales rows or mutate current FIFO inventory. Use `forceRefresh: true` only when the manager intentionally wants to replace the official stored simulation for that date.

---

## 8. Verification Plan

| Step | Command | Expected Result |
|---|---|---|
| 1 | `POST /api/sales/simulate { date: "2026-06-26" }` | Simulation runs, returns summary with 4 categories |
| 2 | `GET /api/sales/2026-06-26` | Returns ~200-400 transactions (4 categories × ~50-100 each) |
| 3 | `GET /api/sales/2026-06-26/summary` | Returns 4 daily_results rows with demand, sold, lost_sales, waste_rate, notes |
| 4 | `GET /api/sales/2026-06-26/slot/morning` | Returns morning-slot transactions only |
| 5 | Check Supabase `sales_transactions` | Rows with timestamps, slot, category, qty 1-3, AND `unit_price` snapshot + `subtotal = quantity * unit_price` |
| 6 | Check Supabase `daily_production` | 4 rows with recommended_qty + actual_produced + production_decision_id when decisions exist |
| 7 | Check Supabase `daily_results` | 4 rows with demand, sold, lost_sales, error_pct, AND financial cache: `revenue` = SUM(subtotal), `ingredient_cost` = produced * costPerUnit, `gross_profit` = revenue - ingredient_cost |
| 8 | Check Supabase `inventory_log` | Deduction entries with reason "daily_production" and FIFO `batch_id` values |
| 9 | Set low production via producedOverride, simulate | See stock-out: lost_sales > 0, leftover = 0 |
| 10 | `POST /api/sales/simulate { date: "2026-06-26", forceRefresh: true }` | Re-simulates: old data deleted, inventory restored, new data inserted |
| 11 | Check `inventory_log` after re-simulation | Reversal correction batch entries + new FIFO deduction entries |
| 11b | `POST /api/sales/simulate { date: "2026-06-10", dryRun: true }` | Historical as-of rerun returns a summary but does not delete/insert sales rows or mutate inventory |
| 12 | `PATCH /api/sales/2026-06-26/summary/{categoryId}` | Corrects produced/sold/demand/lost_sales/notes and recalculates derived metrics AND recomputes `revenue`/`ingredient_cost`/`gross_profit` |
| 12b | Financial sanity: simulate a high-waste day (low produced vs predicted) | `gross_profit` visibly lower for that day vs a low-waste day at same revenue — proving the thesis |
| 13 | `npm run typecheck` | No type errors |
| 14 | `npm run lint` | No lint errors |
| 15 | Finance-decoupling audit: `rg "selling_price|unit_cost|gross_profit|revenue" src/services/recommendationEngine.ts src/services/constraintChecker.ts ml_server/src/services ml_server/src/features` | **Zero hits** — confirms finance never enters optimisation/prediction |

---

## 9. Implementation Order

1. Add shared types to `backend/shared/types.ts` (SalesTransaction with `unit_price`+`subtotal`; DailyProduction; DailyResult with demand/lost_sales/notes/`revenue`/`ingredient_cost`/`gross_profit`; SimulateRequest; SimulationSummary)
2. Create `src/repositories/salesTransactionRepo.ts`
3. Create `src/repositories/dailyProductionRepo.ts`
4. Extend `src/repositories/dailyResultRepo.ts` (add write + deleteByDate methods to Module 3's version)
5. Create `src/services/salesDistributionService.ts` (pure calc — slot weights, random time, random int)
6. Create `src/services/transactionRecordingService.ts` (writes transactions + production + results, deducts inventory)
7. Create `src/services/simulationService.ts` (core engine)
8. Create `src/services/manualCorrectionService.ts` (correct results, recalculate derived metrics, log correction)
9. Create `src/controllers/salesController.ts` (fills Module 1 stub)
10. Update `src/controllers/index.ts` to register salesController (replace stub)
11. In `simulationService.simulateDay()`, after `lostSales = Math.max(0, demand - produced)`, call `notificationService.emit({ type: 'stock_out', severity: 'warning', title: 'Stock-Out: ' + categoryName, message: lost_sales + ' lost sales on ' + date, relatedId: pred.bread_category_id })` when `lostSales > 0` (dedupe by bread_category_id)
12. Verify: run all verification steps

---

## 10. Cross-Module Updates Required

| # | File | Change |
|---|---|---|
| 1 | `data_foundation/README.md` | Add `demand` + `lost_sales` + `notes` + `revenue` + `ingredient_cost` + `gross_profit` columns to `daily_results`; add `unit_price` + `subtotal` to `sales_transactions`; seed `bread_categories.selling_price` + `ingredients.unit_cost`; flip `ingredients.unit` to commercial bulk unit. (All done in updated Module 0 plan.) |
| 2 | `data_foundation/MODULE.md` | Add columns to `bread_categories`, `ingredients`, `sales_transactions`, `daily_results` entity tables. (Done.) |
| 3 | `inventory_integration/README.md` | Add FIFO-aware deduction/reversal methods to `inventoryService.ts`; **new `ingredientCostCalculator.ts` (reporting-only)** — `costPerUnit(categoryId)` computes ingredient cost per produced unit. Must NOT be imported by `recommendationEngine` or `constraintChecker`. |
| 4 | `nodejs_middleware/MODULE.md` | Build `notificationService.ts` + `pushService.ts` (FCM) + `notificationRepo.ts` + `fcmTokenRepo.ts` + `notificationController.ts` + `firebaseAdminClient.ts` (so POS simulation can import `notificationService`). Also ensure `breadCategoryRepo.findAll()` returns `selling_price`. |

---

## 11. Open Items for Implementation

| # | Item | Notes |
|---|---|---|
| 1 | Prediction must exist before simulation | `/api/sales/simulate` throws if no prediction for the date. Run prediction (Module 2) first. |
| 2 | Weather/holiday must be fetched before simulation | `contextService.fetchContext` handles this automatically (caches in DB, fetches from API if missing) |
| 3 | PRNG determinism | Simulation uses `Math.random()` (non-deterministic). If reproducible simulations are needed, seed the PRNG like the Module 0 seed script does. |
| 4 | Transaction count per slot | With qty 1-3 avg 2, ~50-100 transactions per category. 4 categories = ~200-400 total/day. Confirm this volume is acceptable for Supabase. |
| 5 | Inventory going negative on re-simulation | FIFO reversal is simplified for MVP by adding correction batches. Production-grade reversal would restore exact `inventory_log.batch_id` movements by production run. |

---

**Plan Status:** Complete. Ready for implementation on your signal.
