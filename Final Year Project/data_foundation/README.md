# Module 0: Data Foundation + Supabase Schema — Detailed Plan

**Build Order:** 1st (bedrock — all other modules depend on this)
**Status:** Detailed plan — ready for implementation

> See `MODULE.md` in this folder for the high-level plan (entities, integration points, resolved decisions).
> This README documents the concrete artifacts to build.

**Scope:** Single bakery. No `bakery_id` FK on any table. The `bakeries` table holds one config row only.

---

## 1. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Schema scope | Single-bakery, no `bakery_id` FK | Project is one bakery only — simpler schema, fewer joins |
| 2 | Sales granularity | Raw transactions (every sale stored) | Enables time-of-day learning, flexible aggregation |
| 3 | Supabase environment | Local Docker for dev | Free, offline, fast iteration, reset anytime |
| 4 | Migration tooling | Supabase CLI migrations | Standard for Supabase, integrates with local Docker |
| 5 | Seed data | Deterministic (seeded PRNG) | Reproducible test data across runs |
| 6 | Ingredient units | Normalized to grams | Consistent math across modules |
| 7 | Timestamps | Store in UTC + bakery.timezone offset | Standard practice, avoids ambiguity |

---

## 2. Artifacts to Build

| # | Path | Purpose |
|---|---|---|
| 1 | `backend/supabase/schema/001_initial.sql` | Full DDL — 17 tables, indexes, RLS, triggers, view |
| 2 | `backend/supabase/seed/constants.json` | Shared canonical constants (single source of truth) |
| 3 | `backend/supabase/seed/seed.js` | Node.js seed script — inserts constants + 30-day synthetic history |
| 4 | `backend/supabase/seed/package.json` | Seed script dependencies (@supabase/supabase-js) |
| 5 | `backend/shared/types.ts` | 17 Zod schemas + inferred TS types for Node.js validation |
| 6 | `backend/shared/index.ts` | Barrel export for shared types |
| 7 | `ml_server/src/models.py` | 17 Pydantic models mirroring schema for FastAPI |
| 8 | `flutter_app/lib/models/*.dart` | 7 core Dart data classes for Flutter dashboard |
| 9 | `backend/supabase/README.md` | Setup instructions (local dev + migration commands) |

---

## 3. Database Schema Plan (`001_initial.sql`)

### 3.1 Extensions & Base
```sql
create extension if not exists "pgcrypto";
```

### 3.2 Section A — Core Domain Tables

#### `bakeries` (config — 1 row only)
```sql
create table bakeries (
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
  is_active boolean not null default true
);
```

#### `ingredients`
```sql
create table ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  unit text not null default 'g',
  reorder_threshold numeric
);
```

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

#### `inventory_log`
```sql
create table inventory_log (
  id uuid primary key default gen_random_uuid(),
  inventory_id uuid not null references inventory(id) on delete cascade,
  change_grams numeric not null,
  reason text not null,
  created_at timestamptz not null default now()
);
```

### 3.3 Section B — Prediction & Results Tables

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
  version int not null unique,
  model_type text not null,
  file_path text not null,
  training_start date,
  training_end date,
  mape numeric,
  r_squared numeric,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);
```

#### `daily_predictions`
```sql
create table daily_predictions (
  id uuid primary key default gen_random_uuid(),
  target_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  predicted_demand int not null,
  confidence numeric not null check (confidence >= 0 and confidence <= 100),
  model_version_id uuid references ml_model_versions(id),
  weather_record_id uuid references weather_records(id),
  created_at timestamptz not null default now(),
  unique (target_date, bread_category_id)
);
```

#### `daily_production`
```sql
create table daily_production (
  id uuid primary key default gen_random_uuid(),
  production_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
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
  created_at timestamptz not null default now()
);
```

#### `daily_results`
```sql
create table daily_results (
  id uuid primary key default gen_random_uuid(),
  result_date date not null,
  bread_category_id uuid not null references bread_categories(id) on delete cascade,
  prediction_id uuid references daily_predictions(id),
  predicted int not null,
  produced int not null,
  sold int not null,
  leftover int not null,
  waste_rate_pct numeric,
  error_units int,
  error_pct numeric,
  unique (result_date, bread_category_id)
);
```

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
  charity_partner_id uuid not null references charity_partners(id) on delete cascade,
  donation_date date not null,
  bread_category_id uuid references bread_categories(id),
  quantity int not null,
  status text not null default 'recorded',
  notes text,
  created_at timestamptz not null default now()
);
```

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
create index idx_predictions_target on daily_predictions(target_date);
create index idx_inventory_log_inv on inventory_log(inventory_id);
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
alter table bakeries enable row level security;
alter table bread_categories enable row level security;
alter table ingredients enable row level security;
alter table recipes enable row level security;
alter table inventory enable row level security;
alter table inventory_log enable row level security;
alter table weather_records enable row level security;
alter table calendar_events enable row level security;
alter table daily_predictions enable row level security;
alter table daily_production enable row level security;
alter table sales_transactions enable row level security;
alter table daily_results enable row level security;
alter table charity_partners enable row level security;
alter table donations enable row level security;
alter table ml_model_versions enable row level security;
alter table feature_importance enable row level security;
alter table system_logs enable row level security;

-- Pattern (applied per table for select/insert/update/delete):
-- Single bakery: all authenticated users see all data (no bakery scoping)
create policy "authenticated select" on bread_categories
  for select using (auth.role() = 'authenticated');
create policy "authenticated insert" on bread_categories
  for insert with check (auth.role() = 'authenticated');
create policy "authenticated update" on bread_categories
  for update using (auth.role() = 'authenticated');
create policy "authenticated delete" on bread_categories
  for delete using (auth.role() = 'authenticated');
-- (full set generated in actual file — select/insert/update/delete per table)
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

create trigger trg_bakeries_updated before update on bakeries
  for each row execute function set_updated_at();
create trigger trg_inventory_updated before update on inventory
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
    { "name": "Croissants",  "display_order": 1, "shelf_life_hours": 24 },
    { "name": "Sweet Bread", "display_order": 2, "shelf_life_hours": 24 },
    { "name": "Loaves",      "display_order": 3, "shelf_life_hours": 24 },
    { "name": "Ciabatta",    "display_order": 4, "shelf_life_hours": 24 }
  ],
  "ingredients": [
    { "name": "Flour",  "unit": "g", "reorder_threshold": 5000 },
    { "name": "Butter", "unit": "g", "reorder_threshold": 2000 },
    { "name": "Sugar",  "unit": "g", "reorder_threshold": 2000 },
    { "name": "Yeast",  "unit": "g", "reorder_threshold": 200  },
    { "name": "Salt",   "unit": "g", "reorder_threshold": 500  }
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
  "season_multipliers": {
    "spring": 1.05, "summer": 0.90, "autumn": 1.08, "winter": 1.15
  },
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
├─ step 5: insert inventory (5 rows, starting stock)
├─ step 6: insert charity_partners (3 rows)
├─ step 7: generate 30-day synthetic history:
│    ├─ loop date = (today - 30) .. (yesterday)
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
│    │    │    ├─ insert sales_transactions (per slot, with sale_time)
│    │    │    ├─ insert daily_production row
│    │    │    ├─ insert daily_results row (with error calc)
│    │    │    └─ deduct ingredients from inventory (log in inventory_log)
│    │    └─ end category loop
│    └─ end date loop
├─ step 8: insert initial ml_model_versions row (version 0, inactive)
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
| Inventory | 5 | Initial ingredient levels |
| Charity partners | 3 | Default charities |
| Weather records | 30 | Historical weather |
| Calendar events | ~5 | Holidays/events in range |
| Sales transactions | ~3,600 | 30 days × ~12 transactions/day |
| Daily production | 120 | 30 days × 4 categories |
| Daily results | 120 | 30 days × 4 categories |
| ML model version | 1 | Initial inactive model |
| **Total** | **~3,885** | |

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
  is_active: z.boolean(),
});
export type BreadCategory = z.infer<typeof BreadCategorySchema>;

export const DailyPredictionSchema = z.object({
  id: z.string().uuid(),
  target_date: z.string(),
  bread_category_id: z.string().uuid(),
  predicted_demand: z.number().int(),
  confidence: z.number().min(0).max(100),
  model_version_id: z.string().uuid().nullable(),
  weather_record_id: z.string().uuid().nullable(),
  created_at: z.string(),
});
export type DailyPrediction = z.infer<typeof DailyPredictionSchema>;
// ... (one schema per table — 17 total)
```

**Tables to cover (17):** bakeries, bread_categories, ingredients, recipes, inventory, inventory_log, weather_records, calendar_events, ml_model_versions, daily_predictions, daily_production, sales_transactions, daily_results, charity_partners, donations, feature_importance, system_logs.

---

## 7. Python Models Plan (`ml_server/src/models.py`)

Pydantic models mirroring schema for FastAPI.

```python
from pydantic import BaseModel, Field
from datetime import date, time, datetime
from typing import Optional
from uuid import UUID

class DailyPrediction(BaseModel):
    id: Optional[UUID] = None
    target_date: date
    bread_category_id: UUID
    predicted_demand: int
    confidence: float = Field(ge=0, le=100)
    model_version_id: Optional[UUID] = None
    weather_record_id: Optional[UUID] = None
    created_at: Optional[datetime] = None
# ... (one model per table — 17 total)
```

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
└── models.dart          # barrel export
```

Focus on the 7 entities the dashboard actually renders (read-only UI): bread categories, predictions, results, inventory, donations, weather.

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
│       ├── types.ts                  # 17 Zod schemas
│       └── index.ts                  # Barrel export
│
├── ml_server/                        # Python FastAPI
│   └── src/
│       └── models.py                 # 17 Pydantic models
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
            └── models.dart
```

---

## 11. Verification Plan

After implementation, verify with:

| Step | Command | Expected Result |
|---|---|---|
| 1 | `supabase start` | Local stack boots |
| 2 | `supabase db push` | Migration applies without errors |
| 3 | `node seed.js` | Inserts ~3,885 rows, prints summary |
| 4 | `select count(*) from daily_results;` | 120 (30 days × 4 categories) |
| 5 | `select count(*) from sales_transactions;` | ~3,600 |
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
