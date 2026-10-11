# Module 5: Donation + Dashboard — Detailed Plan

**Build Order:** 6th (depends on Modules 0, 1, 2, 3, 4)
**Status:** Detailed plan — ready for implementation
**Architecture:** View → Controller → Service → Repo/External Adapter (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan (sub-modules, endpoints, data shapes, file structure, Flutter views overview).
> This README documents the concrete artifacts to build: repo methods, service function signatures, controller code, Flutter view examples, verification.

## Revision baseline (authoritative)

- Add category-specific `WasteRecord`/`WasteRepo` and `remainingUnallocatedLeftover`.
- The system may recommend donation or waste, but `LeftoverManagementService` writes neither until the Bakery Manager confirms. Donation plus waste must not exceed the category’s available leftover.
- Replace `DonationController`/auto-donation planning with `LeftoverManagementController` and `LeftoverManagementService`; keep charity and donation status management.
- Include `ReportService`, weekly report generation and `ReportExportAdapter` for supported PDF/CSV output.
- Preserve dashboards, notifications, device-token management and FCM. Flutter uses Node.js REST/SSE/WebSocket for foreground notification data and Supabase only for authentication, never for direct PostgreSQL table subscriptions.
- Flutter screen-level classes use the `View` suffix.

All older auto-donation, mixed-category donation, direct Supabase Realtime, router-as-Controller and missing-waste sketches below are superseded and must be adapted before implementation.

---

## 1. Dependencies (from Modules 0, 1, 3, 4)

| Artifact | Used For |
|---|---|
| Module 0 schema: `donations`, `waste_records`, `charity_partners`, detailed `daily_results` allocation fields | Manager-confirmed leftover allocation |
| Module 0 schema: `daily_results`, `daily_predictions`, `inventory`, `inventory_batches`, `recipes`, `ml_model_versions`, `feature_importance`, `sales_transactions` | Dashboard data aggregation |
| Module 0 `shared/types.ts` | Zod schemas for request/response validation (Model layer) |
| Module 0 Dart models (`flutter_app/lib/models/`) | Flutter data classes |
| Module 1 Express app, auth middleware, Supabase client | This module extends the existing backend |
| Module 1 `repositories/baseRepo.ts` | Base class new repos extend |
| Module 1 `controllers/index.ts` | Register new controllers here |
| Module 2 ML server (via Node.js HTTP proxy) | Dashboard evening/prediction views fetch ML metrics |
| Module 3 `recommendationEngine.generateRecommendation` + `productionDecisionService` | Dashboard morning view calls this and stores manager choice |
| Module 3 `inventoryService.getInventory` + `getLowStockItems` + `getExpiringSoon` + `getInventoryQuality` | Dashboard inventory view reuses this |
| Module 3 `weeklySummaryService.getWeeklySummary` | Dashboard waste view reuses this |
| Module 4 `dailyResultRepo.findByDate` | Donation service reads leftover from daily_results |
| Module 4 `salesTransactionRepo.findByDate` | Dashboard midday/sales views read transactions |

---

## 2. Artifacts to Build

> Layered per `../ARCHITECTURE.md`. TypeScript Repos own Supabase queries. Controller classes call Services; Services call Repos/adapters; Express routers are modules. Screen-level Flutter classes use `View`.

### Backend (Node.js)

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `backend/src/repositories/charityPartnerRepo.ts` | Repo | charity_partners CRUD |
| 2 | `backend/src/repositories/donationRepo.ts` | Repo | donations CRUD + findByDate (write methods; read was in Module 3) |
| 2a | `backend/src/repositories/wasteRepo.ts` | Repo | category-specific manager-confirmed `waste_records` CRUD |
| 3 | `backend/src/services/leftoverManagementService.ts` | Service | Recommend without writing; validate/record manager-confirmed donation or waste and update remaining allocation |
| 4 | `backend/src/services/dashboardService.ts` | Service | Aggregates data for 7 dashboard views |
| 4b | `backend/src/services/financialSummaryService.ts` | Service | **Reporting-only.** Aggregates cached `daily_results.revenue/ingredient_cost/gross_profit` + `sales_transactions.subtotal` for daily/weekly/monthly/lifetime totals + the waste-vs-profit correlation series. Never calls/references `recommendationEngine`; finance never drives optimisation. |
| 4c | `backend/src/services/reportService.ts` | Service | Weekly report generation |
| 4d | `backend/src/adapters/reportExportAdapter.ts` | Adapter | Supported PDF/CSV rendering |
| 5 | `backend/src/controllers/leftoverManagementController.ts` | Controller | Class-based leftover, donation and waste requests |
| 6 | `backend/src/controllers/dashboardController.ts` | Controller | Combined endpoints per view (fills Module 1 stub) + new `/financial` endpoint |
| 7 | `backend/src/routes/*.ts` | Module | Thin route registration |
| 8 | Update `backend/shared/types.ts` | Model | Add CharityPartner, Donation, WasteRecord, allocation/report/export DTOs and dashboard schemas |

### Frontend (Flutter)

| # | Path | Layer | Purpose |
|---|---|---|---|
| 9 | `flutter_app/pubspec.yaml` | — | Flutter dependencies |
| 10 | `flutter_app/lib/main.dart` | — | Entry point |
| 11 | `flutter_app/lib/app.dart` | — | MaterialApp + routing |
| 12 | `flutter_app/lib/services/api_client.dart` | View (infra) | HTTP client to Node.js |
| 13 | `flutter_app/lib/services/auth_service.dart` | View (infra) | Supabase Auth |
| 14 | `flutter_app/lib/services/api_endpoints.dart` | View (infra) | URL constants |
| 15 | `flutter_app/lib/views/login_view.dart` | View | Login screen |
| 16 | `flutter_app/lib/views/home_view.dart` | View | Bottom nav shell (3 tabs + drawer) |
| 17 | `flutter_app/lib/views/morning_view.dart` | View | Today's prediction & plan |
| 18 | `flutter_app/lib/views/midday_view.dart` | View | Real-time sales tracking |
| 19 | `flutter_app/lib/views/evening_view.dart` | View | End of day summary |
| 20 | `flutter_app/lib/views/inventory_view.dart` | View | Stock levels + low-stock + expiring batches + quality status |
| 21 | `flutter_app/lib/views/sales_view.dart` | View | Timeslot distribution + trends |
| 22 | `flutter_app/lib/views/waste_view.dart` | View | Waste rate + donation impact + dual-axis waste-vs-profit chart |
| 23 | `flutter_app/lib/views/prediction_view.dart` | View | Actual-vs-predicted, accuracy, confidence/stability, feature importance |
| 24 | `flutter_app/lib/views/financial_summary_view.dart` | View | **(new)** Revenue/Cost/Gross Profit cards + correlation chart (reporting-only) |
| 24b | `flutter_app/lib/views/weekly_summary_view.dart` | View | Weekly summary per category |
| 25 | `flutter_app/lib/widgets/prediction_card.dart` | View | Reusable prediction card widget |
| 26 | `flutter_app/lib/widgets/inventory_checklist.dart` | View | Ingredient checklist widget |
| 27 | `flutter_app/lib/widgets/sales_tracking_table.dart` | View | Sales tracking table widget |
| 28 | `flutter_app/lib/widgets/daily_results_card.dart` | View | Daily results card widget |
| 29 | `flutter_app/lib/widgets/waste_chart.dart` | View | Waste rate chart widget |
| 30 | `flutter_app/lib/widgets/donation_card.dart` | View | Donation info card widget |
| 31 | `flutter_app/lib/widgets/low_stock_badge.dart` | View | Low-stock alert badge |
| 32 | `flutter_app/lib/widgets/constraint_warning.dart` | View | Constraint warning widget |
| 33 | `flutter_app/lib/widgets/status_indicator.dart` | View | Status indicator widget |
| 33b | `flutter_app/lib/widgets/financial_card.dart` | View | **(new)** Revenue/Ingredient Cost/Gross Profit card widget |
| 33c | `flutter_app/lib/widgets/waste_profit_correlation_chart.dart` | View | **(new)** fl_chart dual-axis line chart: waste_rate_pct vs gross_profit over time |
| 34 | `flutter_app/lib/theme/app_theme.dart` | View | App theme + colors |

---

## 3. Shared Types (add to `backend/shared/types.ts`)

```typescript
// Charity partner
export const CharityPartnerSchema = z.object({
  id: z.string().uuid().optional(),
  name: z.string(),
  contact_info: z.string().nullable().optional(),
  is_active: z.boolean().default(true),
});
export type CharityPartner = z.infer<typeof CharityPartnerSchema>;

// Donation
export const DonationSchema = z.object({
  id: z.string().uuid().optional(),
  charity_partner_id: z.string().uuid(),
  donation_date: z.string(),
  bread_category_id: z.string().uuid().nullable().optional(),
  quantity: z.number().int().positive(),
  status: z.enum(['recorded', 'picked_up', 'delivered']).default('recorded'),
  notes: z.string().nullable().optional(),
  created_at: z.string().optional(),
});
export type Donation = z.infer<typeof DonationSchema>;

// Auto-donate request
export const AutoDonateRequestSchema = z.object({
  body: z.object({
    date: z.string(),
  }),
});
export type AutoDonateRequest = z.infer<typeof AutoDonateRequestSchema>;

// Donation summary
export const DonationSummarySchema = z.object({
  date: z.string(),
  status: z.enum(['donated', 'already_donated', 'no_leftover']),
  charity_partner: z.string().nullable().optional(),
  total_donated: z.number().int(),
  donation_id: z.string().uuid().nullable().optional(),
  items: z.array(z.object({
    bread_category_id: z.string().uuid(),
    category_name: z.string(),
    qty: z.number().int(),
  })),
});
export type DonationSummary = z.infer<typeof DonationSummarySchema>;

// Weekly donation summary
export const WeeklyDonationSummarySchema = z.object({
  week_start: z.string(),
  week_end: z.string(),
  total_donated: z.number().int(),
  total_meals_provided: z.number().int(),
  charity_breakdown: z.array(z.object({
    charity_name: z.string(),
    quantity: z.number().int(),
    donation_days: z.number().int(),
  })),
});
export type WeeklyDonationSummary = z.infer<typeof WeeklyDonationSummarySchema>;

// Dashboard view data shapes
export const MorningViewDataSchema = z.object({
  date: z.string(),
  weather: z.object({
    condition: z.string(),
    temp_high_c: z.number().nullable(),
  }).nullable(),
  holidays: z.array(z.object({
    event_name: z.string(),
    demand_multiplier: z.number(),
  })),
  categories: z.array(z.object({
    bread_category_id: z.string().uuid(),
    category_name: z.string(),
    predicted_demand: z.number().int(),
    confidence: z.number(),
    recommended_production: z.number().int(),
    ingredient_requirements: z.array(z.object({
      ingredient: z.string(),
      need: z.number(),
      have: z.number(),
      sufficient: z.boolean(),
    })),
    constraints: z.array(z.any()),
    options: z.array(z.any()),
  })),
  low_stock_alerts: z.array(z.object({
    ingredient: z.string(),
    current: z.number(),
    threshold: z.number(),
  })),
  all_supplies_ready: z.boolean(),
});
export type MorningViewData = z.infer<typeof MorningViewDataSchema>;

export const MiddayViewDataSchema = z.object({
  date: z.string(),
  current_time: z.string(),
  categories: z.array(z.object({
    bread_category_id: z.string().uuid(),
    category_name: z.string(),
    predicted: z.number().int(),
    sold_so_far: z.number().int(),
    remaining: z.number().int(),
    percent_sold: z.number(),
    status: z.enum(['on_track', 'behind', 'stock_out_risk', 'stock_out']),
  })),
  overall_status: z.enum(['on_track', 'behind', 'stock_out_risk', 'stock_out']),
});
export type MiddayViewData = z.infer<typeof MiddayViewDataSchema>;

export const EveningViewDataSchema = z.object({
  date: z.string(),
  categories: z.array(z.object({
    bread_category_id: z.string().uuid(),
    category_name: z.string(),
    predicted: z.number().int(),
    produced: z.number().int(),
    sold: z.number().int(),
    leftover: z.number().int(),
    demand: z.number().int().nullable(),
    lost_sales: z.number().int().nullable(),
    waste_rate_pct: z.number(),
    accuracy_pct: z.number(),
    revenue: z.number().nonnegative(),          // reporting-only (cached on daily_results)
    ingredient_cost: z.number().nonnegative(),  // cost on PRODUCED units
    gross_profit: z.number(),                   // revenue - ingredient_cost
  })),
  total_produced: z.number().int(),
  total_sold: z.number().int(),
  total_leftover: z.number().int(),
  total_waste_rate: z.number(),
  total_revenue: z.number().nonnegative(),           // reporting-only today's totals
  total_ingredient_cost: z.number().nonnegative(),
  total_gross_profit: z.number(),
  donation: z.object({
    charity: z.string().nullable(),
    quantity: z.number().int().nullable(),
    status: z.string().nullable(),
  }).nullable(),
  ml_models: z.array(z.object({
    category_name: z.string(),
    version: z.number().int().nullable(),
    mape: z.number().nullable(),
    r_squared: z.number().nullable(),
    last_trained: z.string().nullable().optional(),
    accuracy_trend: z.string().nullable(),
  })),
});
export type EveningViewData = z.infer<typeof EveningViewDataSchema>;

// Financial summary (NEW — reporting-only)
export const FinancialSummarySchema = z.object({
  period: z.enum(['today', 'week', 'month', 'lifetime']),
  date_range: z.object({ from: z.string(), to: z.string() }),
  totals: z.object({
    revenue: z.number().nonnegative(),
    ingredient_cost: z.number().nonnegative(),
    gross_profit: z.number(),
  }),
  by_category: z.array(z.object({
    category_name: z.string(),
    revenue: z.number().nonnegative(),
    ingredient_cost: z.number().nonnegative(),
    gross_profit: z.number(),
  })),
  // Paired series for the dual-axis waste-vs-profit chart
  correlation_chart: z.array(z.object({
    date: z.string(),
    waste_rate_pct: z.number(),
    gross_profit: z.number(),
  })),
});
export type FinancialSummary = z.infer<typeof FinancialSummarySchema>;
```

---

## 4. Repositories (Repo Layer — Supabase only)

### 4.1 `src/repositories/charityPartnerRepo.ts`

```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { CharityPartner } from '../../shared/types';

export class CharityPartnerRepo extends BaseRepo<CharityPartner> {
  constructor() { super('charity_partners'); }

  async findActive(): Promise<CharityPartner[]> {
    const { data, error } = await supabase
      .from('charity_partners')
      .select('*')
      .eq('is_active', true)
      .order('name');
    if (error) throw error;
    return data;
  }
}
export const charityPartnerRepo = new CharityPartnerRepo();
```

### 4.2 `src/repositories/donationRepo.ts` (extends Module 3's read-only version)

> Module 3 already defined `findByDateRange` (read, for weekly summary). Module 5 adds write methods for donation creation.

```typescript
import { BaseRepo } from './baseRepo';
import { supabase } from '../config/supabase';
import { Donation } from '../../shared/types';

export class DonationRepo extends BaseRepo<Donation> {
  constructor() { super('donations'); }

  // === From Module 3 (read, for weekly summary) ===
  async findByDateRange(startDate: string, endDate: string): Promise<Donation[]> {
    const { data, error } = await supabase
      .from('donations')
      .select('bread_category_id, quantity, donation_date, charity_partner_id, charity_partners(name)')
      .gte('donation_date', startDate)
      .lte('donation_date', endDate);
    if (error) throw error;
    return data;
  }

  // === NEW in Module 5 (write methods) ===
  async findByDate(donationDate: string): Promise<Donation[]> {
    const { data, error } = await supabase
      .from('donations')
      .select('*, charity_partners(name)')
      .eq('donation_date', donationDate);
    if (error) throw error;
    return data;
  }

  async insert(data: Partial<Donation>): Promise<Donation> {
    const { data: result, error } = await supabase
      .from('donations')
      .insert(data)
      .select()
      .single();
    if (error) throw error;
    return result;
  }

  async updateStatus(id: string, status: string): Promise<void> {
    const { error } = await supabase
      .from('donations')
      .update({ status })
      .eq('id', id);
    if (error) throw error;
  }
}
export const donationRepo = new DonationRepo();
```

---

## 5. Services (Service Layer — business logic, calls repos)

### 5.1 Historical auto-donation sketch (superseded by `LeftoverManagementService`)

> Do not implement `autoDonateLeftovers`. The canonical Service returns a non-persisting recommendation and records `Donation` or `WasteRecord` only after Bakery Manager confirmation, while enforcing `donated + wasted ≤ leftover`.

```typescript
import { donationRepo } from '../repositories/donationRepo';
import { charityPartnerRepo } from '../repositories/charityPartnerRepo';
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { breadCategoryRepo } from '../repositories/breadCategoryRepo';
import { logger } from '../utils/logger';
import { ApiError } from '../utils/apiError';
import { DonationSummary, WeeklyDonationSummary } from '../../shared/types';

export const donationService = {
  async autoDonateLeftovers(date: string): Promise<DonationSummary> {
    // 1. Check if donations already exist for date (idempotent)
    const existing = await donationRepo.findByDate(date);
    if (existing.length > 0) {
      logger.info('Donations already exist for date', { date });
      return {
        date,
        status: 'already_donated',
        charity_partner: existing[0].charity_partners?.name ?? null,
        total_donated: existing.reduce((sum, d) => sum + d.quantity, 0),
        donation_id: existing[0].id,
        items: [],
      };
    }

    // 2. Fetch daily_results for date
    const results = await dailyResultRepo.findByDate(date);
    const leftoverItems = results.filter(r => r.leftover > 0);

    if (leftoverItems.length === 0) {
      logger.info('No leftover to donate', { date });
      return {
        date,
        status: 'no_leftover',
        charity_partner: null,
        total_donated: 0,
        donation_id: null,
        items: [],
      };
    }

    // 3. Pick first active charity partner
    const charities = await charityPartnerRepo.findActive();
    if (charities.length === 0) {
      throw new ApiError(404, 'No active charity partners. Add one first.');
    }
    const charity = charities[0];

    // 4. Fetch category names
    const categories = await breadCategoryRepo.findAll();
    const catMap = new Map(categories.map(c => [c.id, c.name]));

    // 5. Create one donation record (all leftover to one charity)
    const totalLeftover = leftoverItems.reduce((sum, r) => sum + r.leftover, 0);
    const donation = await donationRepo.insert({
      charity_partner_id: charity.id,
      donation_date: date,
      quantity: totalLeftover,
      status: 'recorded',
    });

    logger.info('Auto-donation created', {
      date, charity: charity.name, totalDonated: totalLeftover, donationId: donation.id,
    });

    // 6. Return summary
    return {
      date,
      status: 'donated',
      charity_partner: charity.name,
      total_donated: totalLeftover,
      donation_id: donation.id,
      items: leftoverItems.map(r => ({
        bread_category_id: r.bread_category_id,
        category_name: catMap.get(r.bread_category_id) ?? 'Unknown',
        qty: r.leftover,
      })),
    };
  },

  async recordDonation(data: {
    charity_partner_id: string;
    donation_date: string;
    quantity: number;
    notes?: string;
  }): Promise<Donation> {
    return donationRepo.insert({
      charity_partner_id: data.charity_partner_id,
      donation_date: data.donation_date,
      quantity: data.quantity,
      status: 'recorded',
      notes: data.notes,
    });
  },

  async getDonationsForDate(date: string): Promise<Donation[]> {
    return donationRepo.findByDate(date);
  },

  async getWeeklyDonationSummary(weekStart: string): Promise<WeeklyDonationSummary> {
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);
    const weekEndStr = weekEnd.toISOString().split('T')[0];

    // Fetch donations for the week
    const donations = await donationRepo.findByDateRange(weekStart, weekEndStr);

    // Aggregate per charity
    const charityMap: Record<string, { quantity: number; days: Set<string> }> = {};
    let totalDonated = 0;

    for (const d of donations) {
      const charityName = (d.charity_partners as any)?.name ?? 'Unknown';
      if (!charityMap[charityName]) {
        charityMap[charityName] = { quantity: 0, days: new Set() };
      }
      charityMap[charityName].quantity += d.quantity;
      charityMap[charityName].days.add(d.donation_date);
      totalDonated += d.quantity;
    }

    return {
      week_start: weekStart,
      week_end: weekEndStr,
      total_donated: totalDonated,
      total_meals_provided: totalDonated, // 1 item = 1 meal (simplified)
      charity_breakdown: Object.entries(charityMap).map(([name, data]) => ({
        charity_name: name,
        quantity: data.quantity,
        donation_days: data.days.size,
      })),
    };
  },
};
```

### 5.2 `src/services/dashboardService.ts`

```typescript
import { generateRecommendation } from './recommendationEngine';
import { inventoryService } from './inventoryService';
import { getWeeklySummary } from './weeklySummaryService';
import { predictionRepo } from '../repositories/predictionRepo';
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { salesTransactionRepo } from '../repositories/salesTransactionRepo';
import { donationRepo } from '../repositories/donationRepo';
import { breadCategoryRepo } from '../repositories/breadCategoryRepo';
import { modelVersionRepo } from '../repositories/modelVersionRepo';
import { featureImportanceRepo } from '../repositories/featureImportanceRepo';
import { fetchContext } from './contextService';
import { env } from '../config/env';
import { logger } from '../utils/logger';
import { MorningViewData, MiddayViewData, EveningViewData } from '../../shared/types';

function todayStr(): string {
  return new Date().toISOString().split('T')[0];
}

function currentTimeStr(): string {
  return new Date().toTimeString().split(' ')[0].substring(0, 5);
}

export const dashboardService = {
  // === MORNING VIEW ===
  async getMorningView(): Promise<MorningViewData> {
    const date = todayStr();

    // 1. Get smart recommendation (calls recommendationEngine → ML server + repos)
    const recommendation = await generateRecommendation(date);

    // 2. Get low-stock alerts
    const lowStock = await inventoryService.getLowStockItems();

    // 3. Get weather + holidays
    const context = await fetchContext(date);

    // 4. Determine if all supplies ready
    const allSuppliesReady = recommendation.categories.every(cat =>
      cat.constraints.length === 0
    );

    return {
      date,
      weather: context.weather ? {
        condition: context.weather.condition,
        temp_high_c: context.weather.temp_high_c ?? null,
      } : null,
      holidays: context.calendar.map(c => ({
        event_name: c.event_name ?? 'Unknown',
        demand_multiplier: c.demand_multiplier ?? 1.0,
      })),
      categories: recommendation.categories.map(cat => ({
        bread_category_id: cat.bread_category_id,
        category_name: cat.category_name,
        predicted_demand: cat.predicted_demand,
        confidence: cat.confidence,
        recommended_production: cat.recommended_production,
        ingredient_requirements: cat.ingredient_requirements.map(r => ({
          ingredient: r.ingredient_name,
          need: r.total_grams,
          have: r.have_grams,
          sufficient: r.sufficient,
        })),
        constraints: cat.constraints,
        options: cat.options,
      })),
      low_stock_alerts: lowStock.map(item => ({
        ingredient: item.ingredient_name,
        current: item.quantity_grams,
        threshold: item.reorder_threshold ?? 0,
      })),
      all_supplies_ready: allSuppliesReady,
    };
  },

  // === MIDDAY VIEW ===
  async getMiddayView(): Promise<MiddayViewData> {
    const date = todayStr();
    const currentTime = currentTimeStr();

    // 1. Fetch today's predictions
    const predictions = await predictionRepo.findByDate(date);

    // 2. Fetch sales transactions so far today
    const transactions = await salesTransactionRepo.findByDate(date);

    // 3. Get category names
    const categories = await breadCategoryRepo.findAll();
    const catMap = new Map(categories.map(c => [c.id, c.name]));

    // 4. Calculate sold_so_far + remaining per category
    const soldByCategory = new Map<string, number>();
    for (const t of transactions) {
      const current = soldByCategory.get(t.bread_category_id) ?? 0;
      soldByCategory.set(t.bread_category_id, current + t.quantity);
    }

    const catData = predictions.map(pred => {
      const predicted = pred.predicted_demand;
      const soldSoFar = soldByCategory.get(pred.bread_category_id) ?? 0;
      const remaining = pred.predicted_demand - soldSoFar; // approximation
      const percentSold = predicted > 0 ? (soldSoFar / predicted) * 100 : 0;

      // Status: on_track (>60% by midday), behind (<40%), stock_out_risk (<20%), stock_out (remaining <= 0)
      let status: 'on_track' | 'behind' | 'stock_out_risk' | 'stock_out' = 'on_track';
      if (remaining <= 0) status = 'stock_out';
      else if (percentSold < 20) status = 'stock_out_risk';
      else if (percentSold < 40) status = 'behind';

      return {
        bread_category_id: pred.bread_category_id,
        category_name: catMap.get(pred.bread_category_id) ?? 'Unknown',
        predicted,
        sold_so_far: soldSoFar,
        remaining: Math.max(0, remaining),
        percent_sold: Math.round(percentSold * 100) / 100,
        status,
      };
    });

    // Overall status = worst category status
    const statusOrder = ['on_track', 'behind', 'stock_out_risk', 'stock_out'];
    const overallStatus = catData.reduce((worst, c) =>
      statusOrder.indexOf(c.status) > statusOrder.indexOf(worst) ? c.status : worst,
      'on_track' as const,
    );

    return {
      date,
      current_time: currentTime,
      categories: catData,
      overall_status: overallStatus,
    };
  },

  // === EVENING VIEW ===
  async getEveningView(): Promise<EveningViewData> {
    const date = todayStr();

    // 1. Fetch daily_results for today
    const results = await dailyResultRepo.findByDate(date);

    // 2. Get category names
    const categories = await breadCategoryRepo.findAll();
    const catMap = new Map(categories.map(c => [c.id, c.name]));

    // 3. Fetch donations for today
    const donations = await donationRepo.findByDate(date);
    const donation = donations[0]; // all to one charity per day

    // 4. Fetch active ML model rows (one per category)
    const activeModels = await modelVersionRepo.getActiveAll();

    // 5. Calculate accuracy per category + totals
    const catData = results.map(r => {
      const predicted = r.predicted;
      const sold = r.sold;
      const accuracyPct = sold > 0
        ? (1 - Math.abs(predicted - sold) / sold) * 100
        : 0;

      return {
        bread_category_id: r.bread_category_id,
        category_name: catMap.get(r.bread_category_id) ?? 'Unknown',
        predicted,
        produced: r.produced,
        sold,
        leftover: r.leftover,
        demand: r.demand ?? null,
        lost_sales: r.lost_sales ?? null,
        waste_rate_pct: r.waste_rate_pct ?? 0,
        accuracy_pct: Math.round(accuracyPct * 100) / 100,
        revenue: r.revenue ?? 0,                // reporting-only (cached on daily_results)
        ingredient_cost: r.ingredient_cost ?? 0, // cost on PRODUCED units
        gross_profit: r.gross_profit ?? 0,        // revenue - ingredient_cost
      };
    });

    const totalProduced = catData.reduce((s, c) => s + c.produced, 0);
    const totalSold = catData.reduce((s, c) => s + c.sold, 0);
    const totalLeftover = catData.reduce((s, c) => s + c.leftover, 0);
    const totalWasteRate = totalProduced > 0 ? (totalLeftover / totalProduced) * 100 : 0;
    const totalRevenue = catData.reduce((s, c) => s + c.revenue, 0);
    const totalIngredientCost = catData.reduce((s, c) => s + c.ingredient_cost, 0);
    const totalGrossProfit = catData.reduce((s, c) => s + c.gross_profit, 0);

    // 6. Build per-category model status
    const allVersions = await modelVersionRepo.findAll();
    const mlModels = activeModels.map(model => {
      const prevVersion = allVersions.find(v =>
        v.bread_category_id === model.bread_category_id &&
        v.version === model.version - 1
      );
      const accuracyTrend = prevVersion?.mape && model.mape
        ? (model.mape < prevVersion.mape ? 'improving' : 'stable')
        : null;

      return {
        category_name: catMap.get(model.bread_category_id) ?? 'Unknown',
        version: model.version,
        mape: model.mape,
        r_squared: model.r_squared,
        last_trained: model.created_at,
        accuracy_trend: accuracyTrend,
      };
    });

    return {
      date,
      categories: catData,
      total_produced: totalProduced,
      total_sold: totalSold,
      total_leftover: totalLeftover,
      total_waste_rate: Math.round(totalWasteRate * 100) / 100,
      total_revenue: Math.round(totalRevenue * 100) / 100,
      total_ingredient_cost: Math.round(totalIngredientCost * 100) / 100,
      total_gross_profit: Math.round(totalGrossProfit * 100) / 100,
      donation: donation ? {
        charity: (donation as any).charity_partners?.name ?? null,
        quantity: donation.quantity,
        status: donation.status,
      } : null,
      ml_models: mlModels,
    };
  },

  // === PREDICTION ANALYTICS VIEW ===
  async getPredictionAnalytics(): Promise<any> {
    // 1. Fetch all model versions (accuracy over time)
    const versions = await modelVersionRepo.findAll();

    // 2. Fetch feature importance for active category models
    const activeModels = await modelVersionRepo.getActiveAll();
    let featureImportance: any[] = [];
    for (const model of activeModels) {
      const rows = await featureImportanceRepo.findByVersionId(model.id);
      featureImportance.push(...rows.map(r => ({
        ...r,
        bread_category_id: model.bread_category_id,
      })));
    }

    // 3. Calculate avg confidence/stability across current predictions
    const todayPredictions = await predictionRepo.findByDate(todayStr());
    const avgConfidence = todayPredictions.length > 0
      ? todayPredictions.reduce((sum, p) => sum + p.confidence, 0) / todayPredictions.length
      : 0;

    // 4. Actual-vs-predicted chart data
    const recentResults = await dailyResultRepo.findByDateRange(daysAgoStr(30), todayStr());

    return {
      model_versions: versions.map(v => ({
        bread_category_id: v.bread_category_id,
        version: v.version,
        mape: v.mape,
        r_squared: v.r_squared,
        is_active: v.is_active,
        created_at: v.created_at,
      })),
      active_model_versions: activeModels.map(m => ({
        bread_category_id: m.bread_category_id,
        version: m.version,
      })),
      avg_confidence_stability: Math.round(avgConfidence * 100) / 100,
      actual_vs_predicted: recentResults.map(r => ({
        date: r.result_date,
        bread_category_id: r.bread_category_id,
        predicted: r.predicted,
        sold: r.sold,
      })),
      feature_importance: featureImportance.map(f => ({
        bread_category_id: f.bread_category_id,
        feature_name: f.feature_name,
        importance_score: f.importance_score,
        rank: f.rank,
      })),
    };
  },

  // === INVENTORY VIEW ===
  async getInventoryView(): Promise<any> {
    const inventory = await inventoryService.getInventory();
    const lowStock = await inventoryService.getLowStockItems();
    const expiringSoon = await inventoryService.getExpiringSoon(7);
    const quality = await inventoryService.getInventoryQuality();
    return { inventory, low_stock: lowStock, expiring_soon: expiringSoon, quality };
  },

  // === SALES VIEW ===
  async getSalesView(date: string): Promise<any> {
    const transactions = await salesTransactionRepo.findByDate(date);

    // Aggregate by time_slot + category
    const bySlot: Record<string, Record<string, number>> = {
      morning: {}, afternoon: {}, evening: {},
    };
    for (const t of transactions) {
      const catId = t.bread_category_id;
      bySlot[t.time_slot][catId] = (bySlot[t.time_slot][catId] ?? 0) + t.quantity;
    }

    // Get category names
    const categories = await breadCategoryRepo.findAll();
    const catMap = new Map(categories.map(c => [c.id, c.name]));

    // Reporting-only financial breakdown for the selected date
    const dailyRevenueByCat: Record<string, number> = {};
    let dailyRevenue = 0;
    for (const t of transactions) {
      dailyRevenueByCat[t.bread_category_id] = (dailyRevenueByCat[t.bread_category_id] ?? 0) + (t.subtotal ?? 0);
      dailyRevenue += t.subtotal ?? 0;
    }

    // Best-selling category (highest units sold on this date)
    const catSold: Record<string, number> = {};
    for (const t of transactions) catSold[t.bread_category_id] = (catSold[t.bread_category_id] ?? 0) + t.quantity;
    let bestSelling: { category_name: string; quantity: number } | null = null;
    for (const [catId, qty] of Object.entries(catSold)) {
      if (!bestSelling || qty > bestSelling.quantity) bestSelling = { category_name: catMap.get(catId) ?? 'Unknown', quantity: qty };
    }

    // Period revenue totals (rm cards) — aggregate cached daily_results financial columns
    const today = todayStr();
    const weekAgo = new Date(today); weekAgo.setDate(weekAgo.getDate() - 6);
    const monthAgo = new Date(today); monthAgo.setDate(monthAgo.getDate() - 29);
    const [dayRows, weekRows, monthRows, allRows] = await Promise.all([
      dailyResultRepo.findByDateRange(today, today),
      dailyResultRepo.findByDateRange(weekAgo.toISOString().split('T')[0], today),
      dailyResultRepo.findByDateRange(monthAgo.toISOString().split('T')[0], today),
      dailyResultRepo.findByDateRange('1970-01-01', today),
    ]);
    const sumRev = (rows: any[]) => rows.reduce((s, r) => s + (r.revenue ?? 0), 0);
    const dailyRevenueCard = sumRev(dayRows);
    const weeklyRevenueCard = sumRev(weekRows);
    const monthlyRevenueCard = sumRev(monthRows);
    const lifetimeRevenueCard = sumRev(allRows);

    // Revenue trend (RM) — last 30 days by date
    const revenueTrend = Object.entries(
      monthRows.reduce((acc: Record<string, number>, r) => {
        acc[r.result_date] = (acc[r.result_date] ?? 0) + (r.revenue ?? 0);
        return acc;
      }, {})
    ).map(([date_str, rev]) => ({ date: date_str, revenue: Math.round(rev * 100) / 100 }));

    return {
      date,
      total_transactions: transactions.length,
      total_sold: transactions.reduce((s, t) => s + t.quantity, 0),
      by_slot: Object.entries(bySlot).map(([slot, catMap]) => ({
        slot,
        categories: Object.entries(catMap).map(([catId, qty]) => ({
          bread_category_id: catId,
          category_name: catMap.get(catId) ?? 'Unknown',
          quantity: qty,
        })),
        slot_total: Object.values(catMap).reduce((s, q) => s + q, 0),
      })),
      financial_cards: {                                   // reporting-only — RM revenue cards
        daily: Math.round(dailyRevenueCard * 100) / 100,
        weekly: Math.round(weeklyRevenueCard * 100) / 100,
        monthly: Math.round(monthlyRevenueCard * 100) / 100,
        lifetime: Math.round(lifetimeRevenueCard * 100) / 100,
      },
      revenue_by_category: Object.entries(dailyRevenueByCat).map(([catId, rev]) => ({
        bread_category_id: catId,
        category_name: catMap.get(catId) ?? 'Unknown',
        revenue: Math.round(rev * 100) / 100,
      })),
      revenue_trend: revenueTrend,                         // RM over last 30 days
      best_selling_category: bestSelling,                 // for the "best-selling" pill
    };
  },

  // === WASTE & DONATION VIEW ===
  async getWasteView(weekStart: string): Promise<any> {
    // 1. Fetch weekly summary (from Module 3)
    const weeklySummary = await getWeeklySummary(weekStart);

    // 2. Fetch weekly donation summary (from donationService)
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);
    const weekEndStr = weekEnd.toISOString().split('T')[0];
    const donations = await donationRepo.findByDateRange(weekStart, weekEndStr);

    const totalDonated = donations.reduce((s, d) => s + d.quantity, 0);

    // Aggregate per charity
    const charityMap: Record<string, number> = {};
    for (const d of donations) {
      const name = (d as any).charity_partners?.name ?? 'Unknown';
      charityMap[name] = (charityMap[name] ?? 0) + d.quantity;
    }

    // 3. Dual-axis correlation series: each day's waste_rate_pct vs gross_profit (reporting-only)
    //    As waste falls, profit rises → proves the thesis visually.
    const weekRows = await dailyResultRepo.findByDateRange(weekStart, weekEndStr);
    const grossByDate: Record<string, number> = {};
    const wasteSumByDate: Record<string, number> = {};
    const wasteCountByDate: Record<string, number> = {};
    for (const r of weekRows) {
      grossByDate[r.result_date] = (grossByDate[r.result_date] ?? 0) + (r.gross_profit ?? 0);
      wasteSumByDate[r.result_date] = (wasteSumByDate[r.result_date] ?? 0) + (r.waste_rate_pct ?? 0);
      wasteCountByDate[r.result_date] = (wasteCountByDate[r.result_date] ?? 0) + 1;
    }
    const correlation_chart = Object.keys(grossByDate).sort().map(d => ({
      date: d,
      waste_rate_pct: wasteCountByDate[d] > 0 ? Math.round((wasteSumByDate[d] / wasteCountByDate[d]) * 100) / 100 : 0,
      gross_profit: Math.round(grossByDate[d] * 100) / 100,
    }));

    return {
      week_start: weekStart,
      weekly_summary: weeklySummary,
      total_donated: totalDonated,
      meals_provided: totalDonated,
      charity_breakdown: Object.entries(charityMap).map(([name, qty]) => ({
        charity_name: name,
        quantity: qty,
      })),
      correlation_chart,   // dual-axis chart series (waste_rate_pct vs gross_profit)
    };
  },
};
```

### 5.3 `src/services/financialSummaryService.ts` — REPORTING-ONLY

> **Core philosophy guard:** this service reads only the financial cache (`daily_results.revenue/ingredient_cost/gross_profit`) and `sales_transactions.subtotal`. It must NOT import `recommendationEngine`, `ingredientCostCalculator`, or anything ML. Finance is for visualisation only — proving that less waste → better profit. Audit: `rg "recommendationEngine|ingredientCost" src/services/financialSummaryService.ts` → zero hits.

```typescript
import { dailyResultRepo } from '../repositories/dailyResultRepo';
import { breadCategoryRepo } from '../repositories/breadCategoryRepo';
import { logger } from '../utils/logger';
import { FinancialSummary } from '../../shared/types';

// Reporting-only: all financial figures come from the cache Module 4 writes on daily_results.
// Gross profit uses ingredient_cost of PRODUCED (sold + wasted/donated) — so waste visibly eats profit.
export const financialSummaryService = {
  async getSummary(period: 'today'|'week'|'month'|'lifetime', date?: string): Promise<FinancialSummary> {
    const anchor = date ?? new Date().toISOString().split('T')[0];
    const { from, to } = computeRange(period, anchor);

    // dailyResultRepo.findByDateRange returns rows with revenue/ingredient_cost/gross_profit (cache)
    // and waste_rate_pct + bread_categories(name).
    const rows = await dailyResultRepo.findByDateRange(from, to);

    const totals = { revenue: 0, ingredient_cost: 0, gross_profit: 0 };
    const byCat: Record<string, { category_name: string; revenue: number; ingredient_cost: number; gross_profit: number }> = {};
    const correlation: { date: string; waste_rate_pct: number; gross_profit: number }[] = [];
    const dailyGrossByDate: Record<string, number> = {};
    const dailyWasteByDate: Record<string, number> = {};

    for (const r of rows) {
      const catId = r.bread_category_id;
      const catName = r.bread_categories?.name ?? 'Unknown';
      const rev = r.revenue ?? 0;
      const cost = r.ingredient_cost ?? 0;
      const gp = r.gross_profit ?? 0;

      totals.revenue += rev;
      totals.ingredient_cost += cost;
      totals.gross_profit += gp;

      if (!byCat[catId]) byCat[catId] = { category_name: catName, revenue: 0, ingredient_cost: 0, gross_profit: 0 };
      byCat[catId].revenue += rev;
      byCat[catId].ingredient_cost += cost;
      byCat[catId].gross_profit += gp;

      dailyGrossByDate[r.result_date] = (dailyGrossByDate[r.result_date] ?? 0) + gp;
      // weighted waste by produced for per-day average across categories
      const w = r.produced > 0 ? r.waste_rate_pct ?? 0 : 0;
      dailyWasteByDate[r.result_date] = (dailyWasteByDate[r.result_date] ?? 0) + w; // simple avg across categories
    }

    for (const d of Object.keys(dailyGrossByDate).sort()) {
      correlation.push({
        date: d,
        gross_profit: Math.round(dailyGrossByDate[d] * 100) / 100,
        waste_rate_pct: Math.round((dailyWasteByDate[d] ?? 0) * 100) / 100,
      });
    }

    return {
      period,
      date_range: { from, to },
      totals: {
        revenue: Math.round(totals.revenue * 100) / 100,
        ingredient_cost: Math.round(totals.ingredient_cost * 100) / 100,
        gross_profit: Math.round(totals.gross_profit * 100) / 100,
      },
      by_category: Object.values(byCat).map(c => ({
        ...c,
        revenue: Math.round(c.revenue * 100) / 100,
        ingredient_cost: Math.round(c.ingredient_cost * 100) / 100,
        gross_profit: Math.round(c.gross_profit * 100) / 100,
      })),
      correlation_chart: correlation,
    };
  },
};

function computeRange(period: string, anchor: string) {
  const a = new Date(anchor);
  if (period === 'today') return { from: anchor, to: anchor };
  if (period === 'week') {
    const start = new Date(a); start.setDate(a.getDate() - 6);
    return { from: start.toISOString().split('T')[0], to: anchor };
  }
  if (period === 'month') {
    const start = new Date(a); start.setDate(a.getDate() - 29);
    return { from: start.toISOString().split('T')[0], to: anchor };
  }
  // lifetime
  return { from: '1970-01-01', to: anchor };
}
```

> **Note on `waste_rate_pct` per day:** the simple example above averages per-day waste across categories. A more accurate per-day weighted waste rate would weight each category's `waste_rate_pct` by `produced`. Either form is acceptable for the dual-axis chart's qualitative "as waste falls, profit rises" story; refine during implementation if you want a precise single-day waste curve.

---

## 6. Controllers (Controller Layer — thin HTTP handlers)

### 6.1 Historical Router-as-Controller sketch (superseded)

Use a constructor-injected `LeftoverManagementController` class plus thin Express route modules. The old `donationController = Router()` and `/donations/auto` code below are retained only as historical planning context.

```typescript
import { Router } from 'express';
import { validateRequest } from '../middleware/validateRequest';
import { z } from 'zod';
import { donationService } from '../services/donationService';
import { charityPartnerRepo } from '../repositories/charityPartnerRepo';

export const donationController = Router();

// Charity partner CRUD
donationController.get('/charity-partners', async (req, res, next) => {
  try {
    const partners = await charityPartnerRepo.findAll();
    res.json(partners);
  } catch (err) { next(err); }
});

const CreateCharitySchema = z.object({
  body: z.object({
    name: z.string(),
    contact_info: z.string().optional(),
  }),
});

donationController.post('/charity-partners', validateRequest(CreateCharitySchema), async (req, res, next) => {
  try {
    const partner = await charityPartnerRepo.insert(req.body);
    res.status(201).json(partner);
  } catch (err) { next(err); }
});

const UpdateCharitySchema = z.object({
  body: z.object({
    name: z.string().optional(),
    contact_info: z.string().optional(),
    is_active: z.boolean().optional(),
  }),
});

donationController.put('/charity-partners/:id', validateRequest(UpdateCharitySchema), async (req, res, next) => {
  try {
    const partner = await charityPartnerRepo.update(req.params.id, req.body);
    res.json(partner);
  } catch (err) { next(err); }
});

// Donations
const RecordDonationSchema = z.object({
  body: z.object({
    charity_partner_id: z.string().uuid(),
    donation_date: z.string(),
    quantity: z.number().int().positive(),
    notes: z.string().optional(),
  }),
});

donationController.post('/donations', validateRequest(RecordDonationSchema), async (req, res, next) => {
  try {
    const donation = await donationService.recordDonation(req.body);
    res.status(201).json(donation);
  } catch (err) { next(err); }
});

const AutoDonateSchema = z.object({
  body: z.object({
    date: z.string(),
  }),
});

donationController.post('/donations/auto', validateRequest(AutoDonateSchema), async (req, res, next) => {
  try {
    const summary = await donationService.autoDonateLeftovers(req.body.date);
    res.json(summary);
  } catch (err) { next(err); }
});

donationController.get('/donations/:date', async (req, res, next) => {
  try {
    const donations = await donationService.getDonationsForDate(req.params.date);
    res.json(donations);
  } catch (err) { next(err); }
});

donationController.get('/donations/summary', async (req, res, next) => {
  try {
    const weekStart = (req.query.weekStart as string) || todayStr();
    const summary = await donationService.getWeeklyDonationSummary(weekStart);
    res.json(summary);
  } catch (err) { next(err); }
});

function todayStr(): string {
  return new Date().toISOString().split('T')[0];
}
```

### 6.2 `src/controllers/dashboardController.ts` (fills Module 1 stub)

```typescript
import { Router } from 'express';
import { dashboardService } from '../services/dashboardService';
import { financialSummaryService } from '../services/financialSummaryService';   // reporting-only

export const dashboardController = Router();

dashboardController.get('/dashboard/morning', async (req, res, next) => {
  try {
    const data = await dashboardService.getMorningView();
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/midday', async (req, res, next) => {
  try {
    const data = await dashboardService.getMiddayView();
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/evening', async (req, res, next) => {
  try {
    const data = await dashboardService.getEveningView();
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/prediction', async (req, res, next) => {
  try {
    const data = await dashboardService.getPredictionAnalytics();
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/inventory', async (req, res, next) => {
  try {
    const data = await dashboardService.getInventoryView();
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/sales', async (req, res, next) => {
  try {
    const date = (req.query.date as string) || new Date().toISOString().split('T')[0];
    const data = await dashboardService.getSalesView(date);
    res.json(data);
  } catch (err) { next(err); }
});

dashboardController.get('/dashboard/waste', async (req, res, next) => {
  try {
    const weekStart = (req.query.weekStart as string) || new Date().toISOString().split('T')[0];
    const data = await dashboardService.getWasteView(weekStart);
    res.json(data);
  } catch (err) { next(err); }
});

// NEW — reporting-only endpoint. Finance never drives production; view for the dashboard only.
dashboardController.get('/dashboard/financial', async (req, res, next) => {
  try {
    const period = (req.query.period as 'today'|'week'|'month'|'lifetime') || 'today';
    const date = (req.query.date as string) || undefined;
    const summary = await financialSummaryService.getSummary(period, date);
    res.json(summary);
  } catch (err) { next(err); }
});
```

### 6.3 Update `src/controllers/index.ts`

Replace the stub imports with the real controllers:

```typescript
import { donationController } from './donationController';
import { dashboardController } from './dashboardController';
// ... other imports ...
router.use(donationController);
router.use(dashboardController);
```

---

## 7. Flutter App

### 7.1 `pubspec.yaml`

```yaml
name: bakery_dashboard
description: Smart Bakery Food Waste Reduction System — Manager Dashboard
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.5.0
  dio: ^5.4.0
  fl_chart: ^0.68.0
  intl: ^0.19.0
  provider: ^6.1.0
  go_router: ^14.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

### 7.2 `lib/services/api_client.dart`

```dart
import 'package:dio/dio.dart';
import 'api_endpoints.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  ApiClient._internal() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Attach auth token from Supabase session
        // final token = Supabase.instance.client.auth.currentSession?.accessToken;
        // if (token != null) options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      },
    ));
  }

  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic) parser,
  }) async {
    final response = await _dio.get(path, queryParameters: query);
    return parser(response.data);
  }

  Future<T> post<T>(
    String path, {
    dynamic body,
    required T Function(dynamic) parser,
  }) async {
    final response = await _dio.post(path, data: body);
    return parser(response.data);
  }

  Future<T> put<T>(
    String path, {
    dynamic body,
    required T Function(dynamic) parser,
  }) async {
    final response = await _dio.put(path, data: body);
    return parser(response.data);
  }
}
```

### 7.3 `lib/services/api_endpoints.dart`

```dart
class ApiEndpoints {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api', // Android emulator → host machine
  );

  // Dashboard
  static const String morning = '/dashboard/morning';
  static const String midday = '/dashboard/midday';
  static const String evening = '/dashboard/evening';
  static const String prediction = '/dashboard/prediction';
  static const String inventory = '/dashboard/inventory';
  static const String financial = '/dashboard/financial';   // reporting-only
  static String financialFor(String period, [String? date]) =>
      '/dashboard/financial?period=$period${date != null ? '&date=$date' : ''}';
  static String sales([String? date]) => '/dashboard/sales${date != null ? '?date=$date' : ''}';
  static String waste([String? weekStart]) => '/dashboard/waste${weekStart != null ? '?weekStart=$weekStart' : ''}';

  // Donation
  static const String charityPartners = '/charity-partners';
  static const String donationsAuto = '/donations/auto';
  static String donationsForDate(String date) => '/donations/$date';
  static String donationsSummary([String? weekStart]) =>
      '/donations/summary${weekStart != null ? '?weekStart=$weekStart' : ''}';

  // Inventory
  static const String inventoryList = '/inventory';
  static const String inventoryRestock = '/inventory/restock';
  static const String inventoryLowStock = '/inventory/low-stock';
}
```

### 7.4 `lib/views/home_view.dart` — Bottom nav shell

```dart
import 'package:flutter/material.dart';
import 'morning_view.dart';
import 'midday_view.dart';
import 'evening_view.dart';
import 'inventory_view.dart';
import 'sales_view.dart';
import 'waste_view.dart';
import 'prediction_view.dart';
import 'financial_summary_view.dart';   // (new) reporting-only
import 'weekly_summary_view.dart';

class HomeView extends StatefulWidget {
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;

  final _views = [
    MorningView(),
    MiddayView(),
    EveningView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sweet Bakery Dashboard')),
      body: _views[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny), label: 'Morning'),
          NavigationDestination(icon: Icon(Icons.wb_cloudy), label: 'Midday'),
          NavigationDestination(icon: Icon(Icons.nights_stay), label: 'Evening'),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(child: Text('Analytics')),
            ListTile(
              leading: Icon(Icons.inventory),
              title: Text('Inventory'),
              onTap: () => _navigateTo(context, InventoryView()),
            ),
            ListTile(
              leading: Icon(Icons.point_of_sale),
              title: Text('Sales'),
              onTap: () => _navigateTo(context, SalesView()),
            ),
            ListTile(
              leading: Icon(Icons.recycling),
              title: Text('Waste & Donation'),
              onTap: () => _navigateTo(context, WasteView()),
            ),
            ListTile(
              leading: Icon(Icons.attach_money),
              title: Text('Financial Summary'),
              onTap: () => _navigateTo(context, FinancialSummaryView()),
            ),
            ListTile(
              leading: Icon(Icons.psychology),
              title: Text('Prediction'),
              onTap: () => _navigateTo(context, PredictionView()),
            ),
            ListTile(
              leading: Icon(Icons.calendar_month),
              title: Text('Weekly Summary'),
              onTap: () => _navigateTo(context, WeeklySummaryView()),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget view) {
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => view));
  }
}
```

### 7.5 `lib/views/morning_view.dart` — Example view

```dart
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_endpoints.dart';
import '../widgets/prediction_card.dart';
import '../widgets/inventory_checklist.dart';
import '../widgets/low_stock_badge.dart';
import '../widgets/status_indicator.dart';
import '../widgets/constraint_warning.dart';

class MorningView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ApiClient().get(ApiEndpoints.morning, parser: (d) => d),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final data = snapshot.data as Map<String, dynamic>;
        final date = data['date'] as String;
        final weather = data['weather'] as Map<String, dynamic>?;
        final holidays = data['holidays'] as List<dynamic>;
        final categories = data['categories'] as List<dynamic>;
        final lowStockAlerts = data['low_stock_alerts'] as List<dynamic>;
        final allReady = data['all_supplies_ready'] as bool;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Weather + Holiday banner
            if (weather != null || holidays.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (weather != null)
                        Text('${weather['condition']} ${weather['temp_high_c'] ?? ''}°C'),
                      if (holidays.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Chip(label: Text('${holidays.first['event_name']}')),
                      ],
                    ],
                  ),
                ),
              ),

            // Prediction cards per category
            ...categories.map((cat) => PredictionCard(data: cat)),

            // Ingredient checklist (from first category)
            if (categories.isNotEmpty)
              InventoryChecklist(requirements: categories.first['ingredient_requirements']),

            // Constraint warnings (if any)
            ...categories
                .where((c) => (c['constraints'] as List).isNotEmpty)
                .map((c) => ConstraintWarning(data: c)),

            // Low-stock alerts
            if (lowStockAlerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Low Stock Alerts', style: Theme.of(context).textTheme.titleMedium),
              ...lowStockAlerts.map((a) => LowStockBadge(data: a)),
            ],

            // Status indicator
            const SizedBox(height: 16),
            StatusIndicator(allReady: allReady),
          ],
        );
      },
    );
  }
}
```

### 7.6 Widget Examples (brief)

```dart
// lib/widgets/prediction_card.dart
class PredictionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const PredictionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['category_name'], style: Theme.of(context).textTheme.titleMedium),
                Chip(label: Text('${data['confidence']}% stability')),
              ],
            ),
            const SizedBox(height: 8),
            Text('Predicted demand: ${data['predicted_demand']} units'),
            Text('Recommended production: ${data['recommended_production']} units',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// lib/widgets/donation_card.dart
class DonationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const DonationCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.volunteer_activism, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${data['quantity']} items donated to ${data['charity'] ?? 'charity'}'),
                  Text('Status: ${data['status']}', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/widgets/waste_chart.dart
class WasteChart extends StatelessWidget {
  final List<Map<String, dynamic>> data; // [{date, waste_rate}]
  const WasteChart({required this.data});

  @override
  Widget build(BuildContext context) {
    // Uses fl_chart LineChart to plot waste rate over time
    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((e) =>
              FlSpot(e.key.toDouble(), (e.value['waste_rate'] as num).toDouble())).toList(),
            isCurved: true,
            color: Colors.blue,
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      )),
    );
  }
}
```

---

## 8. Request Flow — Evening View Example

```
Flutter: GET /api/dashboard/evening
  Authorization: Bearer <jwt>
  ↓
Node.js auth middleware (verify JWT)
  ↓
dashboardController handler (Controller)
  ↓
dashboardService.getEveningView() (Service)
  ├─ dailyResultRepo.findByDate(today) (Repo → Supabase)
  │   → [{ category, predicted, produced, sold, leftover, demand, lost_sales }]
  │
  ├─ breadCategoryRepo.findAll() (Repo → Supabase)
  │   → category name mapping
  │
  ├─ donationRepo.findByDate(today) (Repo → Supabase)
  │   → [{ charity, quantity, status }] (or null if not donated yet)
  │
  ├─ modelVersionRepo.getActiveAll() (Repo → Supabase)
  │   → [{ bread_category_id, version, mape, r_squared }] (per-category ML model metrics)
  │
  ├─ Calculate accuracy_pct per category (pure calc in service)
  ├─ Calculate totals (produced, sold, leftover, waste_rate)
  └─ Determine accuracy_trend (compare to previous model version)
  ↓
Flutter receives: { date, categories, totals, donation, ml_models }
  ↓
Flutter EveningView widget renders:
  ├─ DailyResultsCard per category
  ├─ Total summary row
  ├─ DonationCard (if donation exists)
  └─ ML model status section
```

---

## 9. Verification Plan

### Backend

| Step | Command | Expected Result |
|---|---|---|
| 1 | `POST /api/leftovers/recommend` | Returns recommendation without creating donation/waste |
| 2 | Confirm donation and waste whose combined quantity exceeds leftover | Rejected; remaining allocation unchanged |
| 2a | Confirm valid category donation/waste | Creates the selected record, stores manager/reason where required, and updates remaining unallocated leftover |
| 3 | `GET /api/donations/2026-06-26` | Returns donation record with charity name |
| 4 | `GET /api/donations/summary?weekStart=2026-06-23` | Weekly summary per charity |
| 5 | `GET /api/charity-partners` | List of 3 charity partners (from seed) |
| 6 | `POST /api/charity-partners { name, contact_info }` | New charity partner created |
| 7 | `GET /api/dashboard/morning` | Aggregated morning view (prediction + inventory + low-stock) |
| 8 | `GET /api/dashboard/midday` | Aggregated midday view (sales tracking) |
| 9 | `GET /api/dashboard/evening` | Aggregated evening view (results + donation + ML status) |
| 10 | `GET /api/dashboard/prediction` | Actual-vs-predicted + accuracy over time + feature importance |
| 11 | `GET /api/dashboard/inventory` | Stock levels + low-stock + expiring FIFO batches + quality status |
| 12 | `GET /api/dashboard/sales?date=2026-06-26` | Timeslot distribution **+ 4 RM revenue cards (daily/weekly/monthly/lifetime) + revenue-by-category + revenue-trend + best-selling pill** |
| 13 | `GET /api/dashboard/waste?weekStart=2026-06-23` | Waste rates + donation impact **+ `correlation_chart` payload (waste_rate_pct vs gross_profit) for dual-axis chart** |
| 13b | `GET /api/dashboard/financial?period=week&date=2026-06-26` | **(new)** Financial summary: totals + by_category + correlation_chart. **Reporting-only — never affects prediction.** |
| 13c | Finance-decoupling audit: `rg "selling_price\|unit_cost\|gross_profit\|ingredientCost" src/services/recommendationEngine.ts ml_server/src ml_server/src/features` | **Zero hits** — confirms finance never drives optimisation/prediction |

### Flutter

| Step | Command | Expected Result |
|---|---|---|
| 14 | `cd flutter_app && flutter pub get` | Dependencies installed |
| 15 | `flutter run` | App launches, login screen appears |
| 16 | Login with Supabase Auth | Navigates to HomeView with bottom nav |
| 17 | Morning tab | Shows prediction cards + ingredient checklist + status |
| 18 | Midday tab | Shows sales tracking table with status indicators |
| 19 | Evening tab | Shows daily results + donation card + ML model status |
| 20 | Drawer → Inventory | Shows stock levels + low-stock badges |
| 21 | Drawer → Sales | Shows timeslot distribution chart |
| 22 | Drawer → Waste & Donation | Shows waste rate chart + donation impact |
| 23 | Drawer → Prediction | Shows accuracy chart + feature importance bar chart |
| 24 | Drawer → Weekly Summary | Shows per-category weekly summary with trend indicators |
| 25 | Drawer → Financial Summary | Shows revenue, ingredient cost, gross profit cards + waste-vs-profit chart |
| 26 | Evening tab → "Manage leftovers" | Manager reviews recommendation and confirms donation or waste; updated allocation appears |

---

## 10. Implementation Order

### Backend (items 1-10)
1. Add shared types to `backend/shared/types.ts` (CharityPartner, Donation, view data schemas)
2. Create `src/repositories/charityPartnerRepo.ts`
3. Create `src/repositories/donationRepo.ts` (write methods; extend Module 3's read methods)
4. Create `src/services/donationService.ts` (auto-donate, record, weekly summary)
5. Create `src/services/dashboardService.ts` (7 view aggregators)
6. Create `src/services/financialSummaryService.ts` (reporting-only financial totals + correlation chart; never imports recommendation/ML services)
7. Create `src/controllers/donationController.ts` (fills Module 1 stub)
8. Create `src/controllers/dashboardController.ts` (fills Module 1 stub, imports `financialSummaryService`, exposes `/dashboard/financial`)
9. Update `src/controllers/index.ts` to register both controllers
10. Verify: run backend verification steps 1-13c

### Flutter (items 11-28)
11. Create `pubspec.yaml` + `flutter pub get`
12. Create `lib/main.dart` + `lib/app.dart` (entry point + routing)
13. Create `lib/services/` (api_client.dart, auth_service.dart, api_endpoints.dart with `financial` + `financialFor`)
14. Create `lib/theme/app_theme.dart`
15. Create `lib/widgets/` reusable widgets, including `financial_card.dart`
16. Create `lib/views/login_view.dart`
17. Create `lib/views/home_view.dart` (bottom nav shell + drawer, includes Financial Summary route)
18. Create `lib/views/morning_view.dart`
19. Create `lib/views/midday_view.dart`
20. Create `lib/views/evening_view.dart`
21. Create `lib/views/inventory_view.dart`
22. Create `lib/views/sales_view.dart`
23. Create `lib/views/waste_view.dart`
24. Create `lib/views/prediction_view.dart`
25. Create `lib/views/weekly_summary_view.dart`
26. Create `lib/views/financial_summary_view.dart` (reporting-only revenue/cost/profit cards + correlation chart)
27. Verify: `flutter run` + test all views (steps 14-26)
28. Run finance-decoupling audit from verification step 13c

---

## 11. Cross-Module Dependencies

| Dependency | Impact | Already Exists? |
|---|---|---|
| Module 3 `recommendationEngine.generateRecommendation` + `productionDecisionService` | Dashboard morning view calls this and stores selected option | ✅ Yes |
| Module 3 `inventoryService.getInventory` + `getLowStockItems` + `getExpiringSoon` + `getInventoryQuality` | Dashboard inventory view reuses | ✅ Yes |
| Module 3 `weeklySummaryService.getWeeklySummary` | Dashboard waste view reuses | ✅ Yes |
| Module 4 `dailyResultRepo.findByDate` | Donation service reads leftover | ✅ Yes (added in Module 4) |
| Module 4 `salesTransactionRepo.findByDate` | Dashboard midday/sales views read transactions | ✅ Yes (added in Module 4) |
| Module 2 ML server (via Node.js) | Dashboard evening/prediction views fetch ML metrics via `modelVersionRepo` (Supabase) | ✅ Yes (Module 2 writes to `ml_model_versions`) |
| Module 0 Dart models (`flutter_app/lib/models/`) | Flutter uses data classes | ✅ Yes (defined in Module 0 plan) |

> **Cross-module note:** `../ARCHITECTURE.md` must list `financialSummaryService` under Module 5 and keep the finance-decoupling rule explicit. Module 5 consumes reporting caches only; it must not feed financial values back into ML prediction or the recommendation engine.

---

## 12. Open Items for Implementation

| # | Item | Notes |
|---|---|---|
| 1 | ML metrics in Node.js | Dashboard evening/prediction views need ML metrics (MAPE, R², feature importance). These are stored in Supabase (`ml_model_versions`, `feature_importance`) by Module 2's retrain endpoint — no direct ML server call needed from Node.js. |
| 2 | Flutter state management | Using `provider` (simple). If app grows complex, consider `riverpod` or `bloc`. |
| 3 | Flutter API base URL | Default `http://10.0.2.2:3000/api` for Android emulator. iOS simulator uses `http://localhost:3000/api`. Configure via `--dart-define`. |
| 4 | Foreground update transport | Choose authenticated polling, SSE or a Node.js WebSocket relay; Flutter must not subscribe directly to PostgreSQL changes |
| 5 | Charts library | `fl_chart` chosen for waste/accuracy/sales charts. Alternative: `syncfusion_flutter_charts` (more features but heavier + commercial license). |
| 6 | Donation trigger | Donation remains manager-controlled through the simulation/end-of-day flow. Module 6 sends reminders only; it does not run auto-donation, simulation, or retraining automatically. |

---

**Plan Status:** Complete. Ready for implementation on your signal.
