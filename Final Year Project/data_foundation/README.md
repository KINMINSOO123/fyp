# Module 0: Data Foundation + Supabase Schema — Detailed Plan

**Build Order:** 1st (bedrock — all other modules depend on this)
**Status:** Detailed plan — ready for implementation

> See `MODULE.md` in this folder for the high-level plan (entities, integration points, resolved decisions).
> This README documents the concrete artifacts to build.

**Scope:** Single bakery. No `bakery_id` FK on any table. The `bakery_settings` table holds one config row only.

## Revision baseline (authoritative)

The following revisions supersede conflicting names or database ownership in older illustrative snippets later in this document:

- Add `daily_sales_records` as the validated historical-sales table. Its `data_origin` is one of `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, or `SIMULATION_GENERATED`; `units_sold` is the ML target.
- Keep `daily_results` as the detailed completed POS-simulation result. A successful result creates one validated simulation-origin `daily_sales_records` row per category.
- Rename prediction/result fields to `predicted_units_sold`, `units_sold`, and `estimated_demand`. `lost_sales` and `estimated_demand` are analytical, not training targets.
- Add `waste_records`; require category-specific manager-confirmed donation/waste allocation and maintain `remaining_unallocated_leftover`.
- Add `model_evaluations` and candidate/active/inactive model lifecycle metadata. Evaluation uses chronologically later holdout data and stores MAE, RMSE, MAPE and R² plus origin labels; zero actuals are excluded only from MAPE.
- Only Node.js/Express TypeScript Repos access Supabase PostgreSQL. FastAPI receives validated DTOs and has no database-row Pydantic model set or Supabase repository.

The SQL/type sketches below remain planning examples. Before implementation, their table/field lists must be generated from this revision baseline and `MODULE.md`; a conflicting older identifier is not authoritative.

---

## 1. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Schema scope | Single-bakery, no `bakery_id` FK | Project is one bakery only — simpler schema, fewer joins |
| 2 | Sales granularity | Raw transactions (every sale stored) | Enables time-of-day learning, flexible aggregation |
| 3 | Supabase environment | Local Docker for dev | Free, offline, fast iteration, reset anytime |
| 4 | Migration tooling | Supabase CLI migrations | Standard for Supabase, integrates with local Docker |
| 5 | Seed data | Deterministic (seeded PRNG) | Reproducible test data across runs |
| 6 | Ingredient `unit` field | Stores the **commercial bulk unit** (e.g. "kg"), not the storage unit | Matches how suppliers price ingredients; `unit_cost` is cost per bulk unit. Recipes stay in `grams_per_unit` and inventory in `quantity_grams`; finance-only conversion `cost_per_gram = unit_cost / gramsPerBaseUnit(unit)` happens in `ingredientCostCalculator.` Previously this column was the gram-normalised storage unit; switched per the financial reporting spec. |
| 7 | Timestamps | Store in UTC + bakery.timezone offset | Standard practice, avoids ambiguity |
| 8 | Financial data role | **Reporting/visualisation only** — never used to optimise production or change ingredient choices | Core project philosophy. `selling_price`, `unit_cost`, `revenue`, `ingredient_cost`, `gross_profit` are read only by dashboard/financial services; the ML training target and Smart Recommendation Engine stay purely on units + grams. Gross profit uses ingredient cost of **produced** (not sold) items so waste is visibly reflected as lost profit. |
| 9 | Financial snapshots | `unit_price` on each `sales_transactions` row + `revenue`/`ingredient_cost`/`gross_profit` cached on `daily_results` | Keeps historical totals accurate if `selling_price`/`unit_cost` change; daily cache avoids per-sale recompute for dashboard charts. |
| 10 | Historical as-of reruns | Date-stamped reads + `inventory_log.effective_date` | Re-running a previous date must only use rows that existed before/as of that date. ML history filters with `result_date < target_date`; inventory is reconstructed from logged movements with `effective_date <= target_date` instead of reading the current `inventory` snapshot. |

---

## 2. Artifacts to Build

| # | Path | Purpose |
|---|---|---|
| 1 | `backend/supabase/schema/001_initial.sql` | Full DDL — 19 tables, indexes, RLS, triggers, view |
| 2 | `backend/supabase/seed/constants.json` | Shared canonical constants (single source of truth) |
| 3 | `backend/supabase/seed/seed.js` | Node.js seed script — inserts constants + 90-day synthetic history |
| 4 | `backend/supabase/seed/package.json` | Seed script dependencies (@supabase/supabase-js) |
| 5 | `backend/shared/types.ts` | 19 Zod schemas + inferred TS types for Node.js validation |
| 6 | `backend/shared/index.ts` | Barrel export for shared types |
| 7 | `ml_server/src/models.py` | 19 Pydantic models mirroring schema for FastAPI |
| 8 | `flutter_app/lib/models/*.dart` | 8 core Dart data classes for Flutter dashboard |
| 9 | `backend/supabase/README.md` | Setup instructions (local dev + migration commands) |

---

## 3. Database Schema Plan (`001_initial.sql`)

### 3.1 Extensions & Base
```sql
create extension if not exists "pgcrypto";
```

### 3.2 Section A — Core Domain Tables

#### `bakery_settings` (config — 1 row only)
```sql
create table bakery_settings (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location_type text not null,
  opens_at time not null,
  closes_at time not null,
  timezone text not null default 'Asia/Kuala_Lumpur',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

#### `bread_categories`
```sql
create table bread_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  display_order int not null,
  shelf_life_hours int not null default 24,
  selling_price numeric not null default 0,   -- standard retail price per unit (RM). Reporting-only: never read by prediction/recommendation optimisation.
  is_active boolean not null default true
);
```

#### `ingredients`
```sql
create table ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  unit text not null default 'g',              -- commercial bulk unit (e.g. 'kg' for flour/butter, 'g' for yeast/salt). NOT the storage/recipe unit.
  unit_cost numeric not null default 0,       -- cost per bulk unit (e.g. RM28.00 per kg of butter). Reporting-only: never read by prediction/recommendation optimisation.
  reorder_threshold numeric
);
-- Unit conversion (finance-only helper):
--   cost_per_gram = unit_cost / gramsPerBaseUnit(unit), where gramsPerBaseUnit('kg')=1000, 'g'=1, 'ml'=1
-- Used only by ingredientCostCalculator. recipes.grams_per_unit and inventory.quantity_grams continue using grams directly.

#### `recipes`
```sql
create table recipes (
  id uuid primary key default gen_random_uuid(),
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  ingredient_id uuid not null references ingredients(id) on delete cascade,
  grams_per_unit numeric not null,
  unique (bread_category_id, ingredient_id)
);
```

#### `inventory`
```sql
create table inventory (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null unique references ingredients(id) on delete cascade,
  quantity_grams numeric not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
```

#### `inventory_batches`
```sql
create table inventory_batches (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references ingredients(id) on delete cascade,
  received_date date not null,
  expiry_date date not null,
  initial_quantity_grams numeric not null check (initial_quantity_grams > 0),
  remaining_quantity_grams numeric not null check (remaining_quantity_grams >= 0),
  source text,
  status text not null default 'active'
    check (status in ('active', 'depleted', 'expired', 'discarded')),
  created_at timestamptz not null default now()
);
```

`inventory` is the fast current-stock snapshot. `inventory_batches` is the FIFO/expiry source of truth for deductions. Production consumes active, non-expired batches ordered by `expiry_date`, then `received_date`.

#### `inventory_log`
```sql
create table inventory_log (
  id uuid primary key default gen_random_uuid(),
  inventory_id uuid not null references inventory(id) on delete cascade,
  batch_id uuid references inventory_batches(id) on delete set null,
  change_grams numeric not null,
  reason text not null,
  effective_date date not null,
  created_at timestamptz not null default now()
);
```

`effective_date` is the business date of the stock movement. For example, a production deduction for `2026-06-10` stores `effective_date = '2026-06-10'` even if the simulation is re-run later. This allows historical stock reconstruction without using today's `inventory` snapshot.

### 3.3 Section B — Prediction & Results Tables

#### `daily_sales_records`
```sql
create table daily_sales_records (
  id uuid primary key default gen_random_uuid(),
  sales_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  units_sold int not null check (units_sold >= 0),
  data_origin text not null check (
    data_origin in ('ACTUAL_TRANSACTION', 'IMPORTED_HISTORICAL', 'SIMULATION_GENERATED')
  ),
  is_validated boolean not null default false,
  source_reference_id uuid,
  validation_notes text,
  created_at timestamptz not null default now()
);
```

This is the sole historical observation table used for prediction, training and evaluation. Provenance is never inferred from a missing field.

#### `weather_records`
```sql
create table weather_records (
  id uuid primary key default gen_random_uuid(),
  date date not null unique,
  condition text not null,
  temp_high_c numeric,
  temp_low_c numeric,
  humidity_pct numeric,
  fetched_at timestamptz not null default now()
);
```

#### `calendar_events`
```sql
create table calendar_events (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  event_type text not null,
  event_name text,
  demand_multiplier numeric,
  fetched_at timestamptz not null default now(),
  unique (date, event_type)
);
```

#### `ml_model_versions`
```sql
create table ml_model_versions (
  id uuid primary key default gen_random_uuid(),
  version int not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  model_type text not null,
  file_path text not null,
  training_start date,
  training_end date,
  lifecycle_status text not null default 'candidate'
    check (lifecycle_status in ('candidate', 'active', 'inactive', 'rejected')),
  activated_by uuid references auth.users(id),
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  unique (version, bread_category_id)
);
```

Retraining inserts candidates only. Evaluation and explicit System Administrator activation are separate operations; activation deactivates the current version transactionally. A previous valid inactive version can be restored.

#### `model_evaluations`
```sql
create table model_evaluations (
  id uuid primary key default gen_random_uuid(),
  model_version_id uuid not null references ml_model_versions(id) on delete cascade,
  holdout_start date not null,
  holdout_end date not null,
  data_origins text[] not null,
  evaluation_label text not null,
  mae numeric not null,
  rmse numeric not null,
  mape numeric,
  r_squared numeric,
  sample_count int not null,
  mape_sample_count int not null,
  evaluated_at timestamptz not null default now()
);
```

#### `daily_predictions`
```sql
create table daily_predictions (
  id uuid primary key default gen_random_uuid(),
  target_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  predicted_units_sold int not null,
  confidence numeric not null check (confidence >= 0 and confidence <= 100), -- model confidence/stability score
  model_version_id uuid references ml_model_versions(id),
  weather_record_id uuid references weather_records(id),
  created_at timestamptz not null default now(),
  unique (target_date, bread_category_id)
);
```

#### `production_decisions`
```sql
create table production_decisions (
  id uuid primary key default gen_random_uuid(),
  target_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  prediction_id uuid references daily_predictions(id),
  predicted_units_sold int not null,
  recommended_production int not null,
  max_producible int not null,
  final_selected_qty int not null,
  selected_option text not null
    check (selected_option in ('full_prediction', 'reduced_due_constraint', 'manual_override')),
  decision_reason text,
  confirmed_by uuid references auth.users(id),
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (final_selected_qty >= 0),
  check (final_selected_qty <= max_producible),
  check (
    selected_option = 'full_prediction'
    or nullif(trim(decision_reason), '') is not null
  ),
  check (
    selected_option <> 'full_prediction'
    or final_selected_qty = recommended_production
  ),
  check (
    selected_option <> 'reduced_due_constraint'
    or final_selected_qty < recommended_production
  ),
  unique (target_date, bread_category_id)
);
```

`production_decisions` records confirmation only. It does not deduct ingredient inventory. FIFO inventory deduction happens later when production is recorded by the POS Simulation / transaction recording flow.

Decision semantics:
- `full_prediction`: Manager accepts the recommendation; `final_selected_qty = recommended_production`.
- `reduced_due_constraint`: Manager reduces the quantity; `final_selected_qty < recommended_production` and `decision_reason` is required.
- `manual_override`: Manager manually changes the quantity within `max_producible`; `decision_reason` is required.

#### `daily_production`
```sql
create table daily_production (
  id uuid primary key default gen_random_uuid(),
  production_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  production_decision_id uuid references production_decisions(id),
  recommended_qty int not null,
  actual_produced int not null,
  adjustment_reason text,
  unique (production_date, bread_category_id)
);
```

#### `sales_transactions` (raw — every simulated sale)
```sql
create table sales_transactions (
  id uuid primary key default gen_random_uuid(),
  sale_date date not null,
  sale_time time not null,
  time_slot text not null check (time_slot in ('morning','afternoon','evening')),
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  quantity int not null,
  unit_price numeric not null default 0,   -- snapshot of bread_categories.selling_price at sale moment (RM per unit). Keeps history accurate after price changes.
  subtotal   numeric not null default 0,   -- quantity * unit_price (RM)
  created_at timestamptz not null default now()
);
```

##### Finance snapshot rationale
`unit_price` is copied from `bread_categories.selling_price` when the row is written (POS simulation, Module 4). Old sale rows therefore retain the price in force at sale time even after `selling_price` is updated. This is a row-level snapshot, so no separate price-history table is needed — historical sales totals always re-aggregate correctly by `SUM(subtotal)`.

#### `daily_results`
```sql
create table daily_results (
  id uuid primary key default gen_random_uuid(),
  result_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  prediction_id uuid references daily_predictions(id),
  predicted_units_sold int not null,
  produced int not null,
  units_sold int not null,
  leftover int not null,
  remaining_unallocated_leftover int not null,
  estimated_demand int,          -- units_sold + lost_sales; analysis only
  lost_sales int default 0,
  waste_rate_pct numeric,
  error_units int,
  error_pct numeric,
  notes text,
  revenue         numeric not null default 0,   -- SUM(sales_transactions.subtotal) for this category-day. Cache for fast dashboard charts.
  ingredient_cost numeric not null default 0,   -- cost of all PRODUCED units (sold + leftover). Reporting-only; waste visibly eats profit.
  gross_profit    numeric not null default 0,   -- revenue - ingredient_cost. Proves "less waste = better profit".
  unique (result_date, bread_category_id)
);
```

**Column relationships (after POS simulation, Module 4):**
```
units_sold      ≤ produced                                  ← capped at production
leftover        = produced - units_sold                    ← always ≥ 0
estimated_demand = units_sold + lost_sales                 ← analysis only
remaining_unallocated_leftover = leftover - donated - wasted
waste_rate      = (leftover / produced) × 100
error_pct       = |predicted_units_sold - units_sold| / units_sold × 100
revenue         = SUM(sales_transactions.subtotal WHERE row matches this category-day)
ingredient_cost = produced × costPerUnit(category)         ← cost on PRODUCED, not sold (by design)
gross_profit    = revenue - ingredient_cost               ← therefore waste visibly lowers profit
```

**Financial columns are caching/reporting only.** They are written once at end-of-day in Module 4 and never read back by prediction (Module 2) or the Smart Recommendation Engine (Module 3). Weekly/monthly/lifetime financial totals are computed by the dashboard service as `SUM(revenue)` etc. over these cached daily rows.

### 3.4 Section C — Donation Tables

#### `charity_partners`
```sql
create table charity_partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_info text,
  is_active boolean not null default true
);
```

#### `donations`
```sql
create table donations (
  id uuid primary key default gen_random_uuid(),
  daily_result_id uuid not null references daily_results(id) on delete cascade,
  charity_partner_id uuid not null references charity_partners(id) on delete cascade,
  donation_date date not null,
  bread_category_id uuid not null references bread_categories(id),
  quantity int not null check (quantity > 0),
  status text not null default 'recorded',
  confirmed_by uuid not null references auth.users(id),
  notes text,
  created_at timestamptz not null default now()
);
```

#### `waste_records`
```sql
create table waste_records (
  id uuid primary key default gen_random_uuid(),
  daily_result_id uuid not null references daily_results(id) on delete cascade,
  waste_date date not null,
  bread_category_id uuid not null references bread_categories(id),
  quantity int not null check (quantity > 0),
  disposal_reason text not null,
  confirmed_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
```

Neither table is populated automatically. `LeftoverManagementService` validates and records a Bakery Manager’s confirmed action and keeps donation plus waste within the available leftover.

### 3.5 Section D — ML & System Tables

#### `feature_importance`
```sql
create table feature_importance (
  id uuid primary key default gen_random_uuid(),
  model_version_id uuid not null references ml_model_versions(id) on delete cascade,
  feature_name text not null,
  importance_score numeric not null,
  rank int not null
);
```

#### `system_logs`
```sql
create table system_logs (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  payload jsonb,
  severity text not null default 'info',
  created_at timestamptz not null default now()
);
```

### 3.6 Indexes
```sql
create index idx_sales_date_slot on sales_transactions(sale_date, time_slot);
create index idx_sales_category on sales_transactions(sale_date, bread_category_id);
create index idx_daily_results_date on daily_results(result_date);
create index idx_daily_sales_history on daily_sales_records(bread_category_id, sales_date, data_origin);
create index idx_predictions_target on daily_predictions(target_date);
create index idx_model_evaluations_version on model_evaluations(model_version_id, evaluated_at);
create index idx_production_decisions_date on production_decisions(target_date);
create index idx_inventory_log_inv on inventory_log(inventory_id);
create index idx_inventory_log_effective on inventory_log(effective_date, inventory_id);
create index idx_inventory_batches_fifo on inventory_batches(ingredient_id, status, expiry_date, received_date);
create index idx_inventory_batches_expiry on inventory_batches(status, expiry_date);
create index idx_weather_date on weather_records(date);
```

### 3.7 View — `sales_by_timeslot` (aggregated from raw transactions)
```sql
create view sales_by_timeslot as
select
  sale_date,
  time_slot,
  bread_category_id,
  sum(quantity) as total_sold
from sales_transactions
group by sale_date, time_slot, bread_category_id;
```

### 3.8 RLS Policies (single-bakery — authenticated users only)
```sql
-- Enable RLS on all tables
alter table bakery_settings enable row level security;
alter table bread_categories enable row level security;
alter table ingredients enable row level security;
alter table recipes enable row level security;
alter table inventory enable row level security;
alter table inventory_batches enable row level security;
alter table inventory_log enable row level security;
alter table weather_records enable row level security;
alter table calendar_events enable row level security;
alter table daily_sales_records enable row level security;
alter table daily_predictions enable row level security;
alter table production_decisions enable row level security;
alter table daily_production enable row level security;
alter table sales_transactions enable row level security;
alter table daily_results enable row level security;
alter table charity_partners enable row level security;
alter table donations enable row level security;
alter table waste_records enable row level security;
alter table ml_model_versions enable row level security;
alter table model_evaluations enable row level security;
alter table feature_importance enable row level security;
alter table system_logs enable row level security;

-- No general authenticated-client CRUD policies are created.
-- Node.js/Express uses protected server credentials and TypeScript Repos.
-- Flutter uses the Express API; FastAPI has no Supabase credentials.
-- Add a narrowly scoped client policy only if a future approved requirement needs it.
```

### 3.9 Trigger — auto-update `updated_at`
```sql
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_bakery_settings_updated before update on bakery_settings
  for each row execute function set_updated_at();
create trigger trg_inventory_updated before update on inventory
  for each row execute function set_updated_at();
create trigger trg_production_decisions_updated before update on production_decisions
  for each row execute function set_updated_at();
```

---

## 4. Canonical Constants (`constants.json`)

Single source of truth consumed by seed script, Node.js, Python, and Flutter.

```json
{
  "bakery": {
    "name": "Sweet Bakery",
    "location_type": "office_area",
    "opens_at": "06:00",
    "closes_at": "18:00",
    "timezone": "Asia/Kuala_Lumpur"
  },
  "bread_categories": [
    { "name": "Croissants",  "display_order": 1, "shelf_life_hours": 24, "selling_price": 3.50 },
    { "name": "Sweet Bread", "display_order": 2, "shelf_life_hours": 24, "selling_price": 2.80 },
    { "name": "Loaves",      "display_order": 3, "shelf_life_hours": 24, "selling_price": 2.20 },
    { "name": "Ciabatta",    "display_order": 4, "shelf_life_hours": 24, "selling_price": 2.60 }
  ],
  "ingredients": [
    { "name": "Flour",  "unit": "kg", "unit_cost":  6.00, "reorder_threshold": 5000 },
    { "name": "Butter", "unit": "kg", "unit_cost": 28.00, "reorder_threshold": 2000 },
    { "name": "Sugar",  "unit": "kg", "unit_cost":  4.00, "reorder_threshold": 2000 },
    { "name": "Yeast",  "unit": "g",  "unit_cost":  0.03, "reorder_threshold": 200  },
    { "name": "Salt",   "unit": "g",  "unit_cost":  0.005,"reorder_threshold": 500  }
  ],
  "recipes": {
    "Croissants":  { "Flour": 80, "Butter": 15, "Sugar": 5, "Yeast": 2, "Salt": 1 },
    "Sweet Bread": { "Flour": 70, "Butter": 10, "Sugar": 8, "Yeast": 2, "Salt": 1 },
    "Loaves":      { "Flour": 90, "Butter": 5,  "Sugar": 2, "Yeast": 3, "Salt": 2 },
    "Ciabatta":    { "Flour": 85, "Butter": 3,  "Sugar": 1, "Yeast": 2, "Salt": 2 }
  },
  "time_slots": [
    { "slot": "morning",   "start": "06:00", "end": "11:00", "weight_pct": 40 },
    { "slot": "afternoon", "start": "11:00", "end": "15:00", "weight_pct": 35 },
    { "slot": "evening",   "start": "15:00", "end": "18:00", "weight_pct": 25 }
  ],
  "weather_multipliers": {
    "sunny": 1.10, "rainy": 0.85, "cloudy": 1.00,
    "very_hot": 0.92, "snow": 0.80
  },
  "dow_multipliers": {
    "Monday": 0.95, "Tuesday": 0.97, "Wednesday": 1.02,
    "Thursday": 1.05, "Friday": 1.15, "Saturday": 1.20, "Sunday": 1.08
  },
  "season_multipliers": [
    { "season": "northeast_monsoon", "months": [11,12,1,2,3], "multiplier": 0.90 },
    { "season": "inter_monsoon",     "months": [4,10],        "multiplier": 0.98 },
    { "season": "southwest_monsoon", "months": [5,6,7,8,9],   "multiplier": 1.05 }
  ],
  "base_daily_demand": {
    "Croissants": 100, "Sweet Bread": 65, "Loaves": 45, "Ciabatta": 30
  },
  "charity_partners": [
    { "name": "City Food Bank",      "contact_info": "03-1234-5678" },
    { "name": "Homeless Shelter",    "contact_info": "03-2345-6789" },
    { "name": "Community Kitchen",   "contact_info": "03-3456-7890" }
  ]
}
```

---

## 5. Seed Script Plan (`seed.js`)

### 5.1 Structure
```
seed.js
├─ load constants.json
├─ connect to Supabase (env SUPABASE_URL + SUPABASE_SERVICE_KEY)
├─ step 1: insert bakery (1 row)
├─ step 2: insert bread_categories (4 rows)
├─ step 3: insert ingredients (5 rows)
├─ step 4: insert recipes (20 rows = 4 categories × 5 ingredients)
├─ step 5: insert inventory (5 snapshot rows) + inventory_batches (5-10 FIFO lots)
├─ step 6: insert charity_partners (3 rows)
├─ step 7: generate 90-day synthetic history:
│    ├─ loop date = (today - 90) .. (yesterday)
│    ├─ for each date:
│    │    ├─ pick weather condition (weighted random, deterministic)
│    │    ├─ insert weather_records row
│    │    ├─ check calendar_events (insert holidays if in range)
│    │    ├─ for each bread_category:
│    │    │    ├─ base = base_daily_demand[category]
│    │    │    ├─ × dow_multiplier[dayName]
│    │    │    ├─ × weather_multiplier[condition]
│    │    │    ├─ × season_multiplier[season]
│    │    │    ├─ × holiday_multiplier (if event)
│    │    │    ├─ + gaussianNoise(σ=10%, seeded)
│    │    │    ├─ predicted = round(base)
│    │    │    ├─ produced = round(predicted × 1.05)  // 5% buffer
│    │    │    ├─ distribute sold across 3 time slots by weight_pct
│    │    │    ├─ sold = min(produced, round(base × randomVariation))
│    │    │    ├─ insert sales_transactions (per slot, with sale_time, unit_price snapshot from bread_categories.selling_price, subtotal = quantity * unit_price)
│    │    │    ├─ insert production_decisions row (synthetic manager follows recommendation)
│    │    │    ├─ insert daily_production row
│    │    │    ├─ insert daily_results row (with error calc) + financial cache: revenue = SUM(sales_transactions.subtotal), ingredient_cost = produced * costPerUnit(category), gross_profit = revenue - ingredient_cost
│    │    │    ├─ insert validated daily_sales_records row with units_sold and data_origin = SIMULATION_GENERATED
│    │    │    └─ deduct ingredients using FIFO batches, update inventory snapshot, log in inventory_log with effective_date = simulated date
│    │    └─ end category loop
│    └─ end date loop
├─ step 8: leave ml_model_versions/model_evaluations empty until administrator-initiated candidate training
└─ log summary: "Seeded X rows across Y tables"
```

### 5.2 Key Design Points
- Uses a **seeded PRNG** (`mulberry32`) so re-running produces identical data
- **Idempotent**: checks if bakery exists before inserting; truncates/cascades if `--reset` flag passed
- All inserts use service-role key (bypasses RLS for seeding)
- CLI: `node seed.js` (normal) or `node seed.js --reset` (wipe + reseed)

### 5.3 Seed Data Volume

| Dataset | Rows | Purpose |
|---|---|---|
| Bakery | 1 | Single bakery config |
| Bread categories | 4 | Canonical categories |
| Ingredients | 5 | Canonical ingredients |
| Recipes | 20 | 4 categories × 5 ingredients |
| Inventory | 5 | Initial ingredient snapshot totals |
| Inventory batches | 5-10 | FIFO/expiry lots behind the snapshot |
| Charity partners | 3 | Default charities |
| Weather records | 90 | Historical weather |
| Calendar events | ~10-15 | Holidays/events in range |
| Sales transactions | ~10,800 | 90 days × ~12 transactions/day |
| Production decisions | 360 | 90 days × 4 categories |
| Daily production | 360 | 90 days × 4 categories |
| Daily results | 360 | 90 days × 4 categories |
| Daily sales records | 360 | Same synthetic outcomes, explicitly marked `SIMULATION_GENERATED` |
| ML model version | 0 | Cold-start mode is used until first retrain |
| **Total** | **~11,764-11,769** | |

---

## 6. TypeScript Types Plan (`backend/shared/types.ts`)

One Zod schema per table → inferred TypeScript type. Exported from a single `shared/types.ts` so all Node.js routes validate against DB shape.

```typescript
import { z } from 'zod';

export const BreadCategorySchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  display_order: z.number().int(),
  shelf_life_hours: z.number().int(),
  selling_price: z.number().nonnegative(),   // RM per unit — reporting only
  is_active: z.boolean(),
});
export type BreadCategory = z.infer<typeof BreadCategorySchema>;

export const IngredientSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  unit: z.string(),                           // commercial bulk unit ('kg' / 'g' / 'ml')
  unit_cost: z.number().nonnegative(),       // RM per bulk unit — reporting only
  reorder_threshold: z.number().nullable(),
});
export type Ingredient = z.infer<typeof IngredientSchema>;

export const SalesTransactionSchema = z.object({
  id: z.string().uuid(),
  sale_date: z.string(),
  sale_time: z.string(),
  time_slot: z.enum(['morning', 'afternoon', 'evening']),
  bread_category_id: z.string().uuid(),
  quantity: z.number().int().positive(),
  unit_price: z.number().nonnegative(),     // snapshot at sale moment
  subtotal: z.number().nonnegative(),        // quantity * unit_price
  created_at: z.string(),
});
export type SalesTransaction = z.infer<typeof SalesTransactionSchema>;

// DailyResult: add revenue, ingredient_cost, gross_profit (numeric, default 0) — reporting-only cache

export const DailyPredictionSchema = z.object({
  id: z.string().uuid(),
  target_date: z.string(),
  bread_category_id: z.string().uuid(),
  predicted_units_sold: z.number().int(),
  confidence: z.number().min(0).max(100), // confidence/stability score
  model_version_id: z.string().uuid().nullable(),
  weather_record_id: z.string().uuid().nullable(),
  created_at: z.string(),
});
export type DailyPrediction = z.infer<typeof DailyPredictionSchema>;

export const ProductionDecisionSchema = z.object({
  id: z.string().uuid(),
  target_date: z.string(),
  bread_category_id: z.string().uuid(),
  prediction_id: z.string().uuid().nullable(),
  predicted_units_sold: z.number().int(),
  recommended_production: z.number().int(),
  max_producible: z.number().int().nonnegative(),
  final_selected_qty: z.number().int().nonnegative(),
  selected_option: z.enum(['full_prediction', 'reduced_due_constraint', 'manual_override']),
  decision_reason: z.string().nullable(),
  confirmed_by: z.string().uuid().nullable(),
  confirmed_at: z.string(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type ProductionDecision = z.infer<typeof ProductionDecisionSchema>;
// Additional canonical schemas include DataOrigin, DailySalesRecord,
// WasteRecord, ModelEvaluation and the revised DailyResult allocation fields.
```

**Tables to cover:** bakery_settings, bread_categories, ingredients, recipes, inventory, inventory_batches, inventory_log, weather_records, calendar_events, daily_sales_records, ml_model_versions, model_evaluations, daily_predictions, production_decisions, daily_production, sales_transactions, daily_results, charity_partners, donations, waste_records, feature_importance, system_logs, notifications and device-token/user-support tables defined by Module 1.

---

## 7. Python Contract Models Plan (`ml_server/src/contracts/`)

FastAPI Pydantic models mirror only the versioned process-boundary DTOs, not Supabase tables:

- `PredictionRequest`, `PredictionCategoryInput`, `PredictionResponse` and `PredictionResult`
- `TrainingRequest`, `TrainingObservation` and `TrainingResult`
- `EvaluationRequest`, `EvaluationResult` and `ModelMetrics`

Each training/evaluation observation includes `unitsSold` and `DataOrigin`. Node.js supplies validated records, contextual data and active/candidate artifact identifiers. FastAPI returns results and never reads or writes Supabase.

---

## 8. Dart Models Plan (`flutter_app/lib/models/`)

Dart data classes with `json_serializable` or `freezed`.

```
flutter_app/lib/models/
├── bread_category.dart
├── daily_prediction.dart
├── daily_result.dart
├── inventory.dart
├── donation.dart
├── weather_record.dart
├── production_decision.dart
└── models.dart          # barrel export
```

Focus on API DTOs actually rendered by the Views, including category-specific leftover allocation (`DailyResult`, `Donation`, `WasteRecord`) and model-management status. Dart models are not direct PostgreSQL bindings.

---

## 9. Setup README (`backend/supabase/README.md`)

```
## Local Setup
1. Install Supabase CLI: npm i -g supabase
2. Start local stack: supabase start
3. Run migration: supabase db push
4. Seed data: cd seed && node seed.js
5. Reset: supabase db reset && node seed.js --reset

## Env vars
SUPABASE_URL=http://localhost:54321
SUPABASE_SERVICE_KEY=... (from supabase status)
```

---

## 10. Repo Structure After Build

```
fyp/
├── Final Year Project/               # Planning docs
│   ├── fyp_food_waste.md
│   └── data_foundation/
│       ├── MODULE.md                 # High-level plan
│       └── README.md                 # <-- THIS detailed plan
│
├── backend/                          # Node.js middleware
│   ├── supabase/
│   │   ├── schema/
│   │   │   └── 001_initial.sql       # Full DDL
│   │   ├── seed/
│   │   │   ├── constants.json        # Canonical constants
│   │   │   ├── seed.js               # Seed script
│   │   │   └── package.json          # Deps
│   │   └── README.md                 # Setup instructions
│   └── shared/
│       ├── types.ts                  # 19 Zod schemas
│       └── index.ts                  # Barrel export
│
├── ml_server/                        # Python FastAPI
│   └── src/
│       └── models.py                 # 19 Pydantic models
│
└── flutter_app/                      # Flutter dashboard
    └── lib/
        └── models/
            ├── bread_category.dart
            ├── daily_prediction.dart
            ├── daily_result.dart
            ├── inventory.dart
            ├── donation.dart
            ├── weather_record.dart
            ├── production_decision.dart
            └── models.dart
```

---

## 11. Verification Plan

After implementation, verify with:

| Step | Command | Expected Result |
|---|---|---|
| 1 | `supabase start` | Local stack boots |
| 2 | `supabase db push` | Migration applies without errors |
| 3 | `node seed.js` | Inserts ~11,764-11,769 rows, prints summary |
| 4 | `select count(*) from daily_results;` | 360 (90 days × 4 categories) |
| 5 | `select count(*) from sales_transactions;` | ~10,800 |
| 6 | `select * from sales_by_timeslot limit 5;` | View returns aggregated rows |
| 7 | RLS test: unauthenticated query | Blocked (no rows) |

---

## 12. Implementation Order

When building, execute in this sequence:

1. Create `backend/supabase/schema/001_initial.sql` (the DDL — everything depends on it)
2. Create `backend/supabase/seed/constants.json` (seed script reads this)
3. Create `backend/supabase/seed/package.json` + `seed.js` (seed script)
4. Create `backend/shared/types.ts` + `index.ts` (Node.js types)
5. Create `ml_server/src/models.py` (Python types)
6. Create `flutter_app/lib/models/*.dart` (Dart types)
7. Update `backend/supabase/README.md` (setup docs)
8. Verify: `supabase start` → `db push` → `node seed.js` → run verification queries

---

**Plan Status:** Complete. Ready for implementation on your signal.
