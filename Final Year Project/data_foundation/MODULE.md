# Module 0: Data Foundation + Supabase Schema

**Build Order:** 1st (bedrock — all other modules depend on this)
**Status:** High-Level Plan — ready for detailed breakdown

---

## 1. Goal

Define every domain entity, database table, and canonical constant the system shares. One source of truth for schema, types, and seed data so every module (Node.js, Python ML, Flutter) speaks the same language.

**Scope:** Single bakery. No `bakery_id` foreign key on any table. The `bakeries` table holds one config row only.

---

## 2. Dependencies

- None. This is the first thing built.

---

## 3. Domain Entities

Every entity that exists in the system (single bakery scope, no multi-tenancy):

| Entity | Description | Table Name |
|---|---|---|
| Bakery Profile | Single bakery config (name, hours, location type) — 1 row | `bakeries` |
| User / Staff | Login accounts for dashboard access | `users` (Supabase Auth) |
| Bread Category | Canonical bread types tracked | `bread_categories` |
| Recipe | Per-category ingredient requirements | `recipes` |
| Ingredient | Raw materials tracked in inventory | `ingredients` |
| Inventory Snapshot | Current stock level of each ingredient | `inventory` |
| Daily Prediction | ML output per category per day | `daily_predictions` |
| Daily Production | What was actually produced per category | `daily_production` |
| Sales Transaction | Individual sale (from POS simulation) | `sales_transactions` |
| Sales Time Slot | Morning / Afternoon / Evening aggregation | `sales_by_timeslot` (VIEW) |
| End-of-Day Summary | Daily aggregated results per category | `daily_results` |
| Donation Record | Leftover donation to charity | `donations` |
| Charity Partner | Organization receiving donations | `charity_partners` |
| Weather Record | Daily weather snapshot from API | `weather_records` |
| Calendar Event | Holiday / event status from Calendar API | `calendar_events` |
| ML Model Version | Trained model metadata | `ml_model_versions` |
| Feature Importance | Per-model feature weights | `feature_importance` |
| System Log | Operational audit trail | `system_logs` |

---

## 4. Database Schema (Supabase / PostgreSQL)

> **No `bakery_id` FK on any table.** The `bakeries` table is a standalone config table with one row. All other tables belong to the single bakery implicitly.

### 4.1 Core Domain Tables

#### `bakeries` (config — 1 row only)
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK, default gen_random_uuid() | |
| name | text | NOT NULL | e.g. "Sweet Bakery" |
| location_type | text | NOT NULL | e.g. "office_area", "residential", "school_zone" |
| opens_at | time | NOT NULL | e.g. "06:00" |
| closes_at | time | NOT NULL | e.g. "18:00" |
| timezone | text | NOT NULL | e.g. "Asia/Kuala_Lumpur" |
| created_at | timestamptz | NOT NULL, default now() | |
| updated_at | timestamptz | NOT NULL, default now() | |

#### `bread_categories`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| name | text | NOT NULL | e.g. "Croissants" |
| display_order | int | NOT NULL | For UI ordering |
| shelf_life_hours | int | NOT NULL, default 24 | |
| is_active | boolean | NOT NULL, default true | Soft-delete |

Unique: `(name)`.

#### `ingredients`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| name | text | NOT NULL | e.g. "Flour", "Butter", "Sugar", "Yeast", "Salt" |
| unit | text | NOT NULL | e.g. "g", "kg", "ml", "units" |
| reorder_threshold | numeric | | Alert when stock falls below |

Unique: `(name)`.

#### `recipes`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| ingredient_id | uuid | FK → ingredients.id, NOT NULL | |
| grams_per_unit | numeric | NOT NULL | e.g. 80g flour per croissant |

Unique: `(bread_category_id, ingredient_id)`.

#### `inventory`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| ingredient_id | uuid | FK → ingredients.id, NOT NULL | |
| quantity_grams | numeric | NOT NULL | In grams (normalized unit) |
| updated_at | timestamptz | NOT NULL, default now() | |
| updated_by | uuid | FK → auth.users.id | Who logged the update |

Unique: `(ingredient_id)`.

#### `inventory_log`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| inventory_id | uuid | FK → inventory.id | |
| change_grams | numeric | NOT NULL | Positive = restock, negative = used |
| reason | text | NOT NULL | "daily_production", "manual_restock", "spoilage" |
| created_at | timestamptz | NOT NULL, default now() | |

### 4.2 Prediction & Results Tables

#### `weather_records`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| date | date | NOT NULL | |
| condition | text | NOT NULL | "sunny", "rainy", "cloudy", "snow" |
| temp_high_c | numeric | | Celsius |
| temp_low_c | numeric | | |
| humidity_pct | numeric | | |
| fetched_at | timestamptz | NOT NULL | When API was called |

Unique: `(date)`.

#### `calendar_events`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| date | date | NOT NULL | |
| event_type | text | NOT NULL | "public_holiday", "school_holiday", "local_event", "religious_holiday" |
| event_name | text | | e.g. "Independence Day", "Ramadan" |
| demand_multiplier | numeric | | e.g. 1.30 for +30% |
| fetched_at | timestamptz | NOT NULL | |

Unique: `(date, event_type)`.

#### `daily_predictions`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| target_date | date | NOT NULL | The day being predicted FOR |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| predicted_demand | int | NOT NULL | Units predicted |
| confidence | numeric | NOT NULL, CHECK 0-100 | Percentage |
| model_version_id | uuid | FK → ml_model_versions.id | Which model made this |
| weather_record_id | uuid | FK → weather_records.id | Weather data used |
| created_at | timestamptz | NOT NULL, default now() | |

Unique: `(target_date, bread_category_id)`.

#### `daily_production`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| production_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| recommended_qty | int | NOT NULL | What system recommended |
| actual_produced | int | NOT NULL | What was actually baked |
| adjustment_reason | text | | e.g. "yeast_shortage", "override" |

Unique: `(production_date, bread_category_id)`.

#### `sales_transactions`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| sale_date | date | NOT NULL | |
| sale_time | time | NOT NULL | |
| time_slot | text | NOT NULL | "morning", "afternoon", "evening" |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| quantity | int | NOT NULL | |
| created_at | timestamptz | NOT NULL, default now() | |

Index: `(sale_date, time_slot)` for aggregations.

#### `sales_by_timeslot` (VIEW — aggregated from sales_transactions)
| Column | Type | Notes |
|---|---|---|
| sale_date | date | |
| time_slot | text | "morning", "afternoon", "evening" |
| bread_category_id | uuid | |
| total_sold | int | Aggregated from transactions |

#### `daily_results`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| result_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| prediction_id | uuid | FK → daily_predictions.id | Links to what was predicted |
| predicted | int | NOT NULL | Snapshot of prediction |
| produced | int | NOT NULL | Snapshot of production |
| sold | int | NOT NULL | Sum from sales_transactions |
| leftover | int | NOT NULL | produced - sold |
| waste_rate_pct | numeric | | (leftover / produced) * 100 |
| error_units | int | | produced - sold |
| error_pct | numeric | | prediction accuracy |

Unique: `(result_date, bread_category_id)`.

### 4.3 Donation Tables

#### `charity_partners`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| name | text | NOT NULL | e.g. "City Food Bank" |
| contact_info | text | | Phone, email |
| is_active | boolean | NOT NULL, default true | |

#### `donations`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| charity_partner_id | uuid | FK → charity_partners.id, NOT NULL | |
| donation_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id | Can be null if mixed |
| quantity | int | NOT NULL | |
| status | text | NOT NULL | "recorded", "picked_up", "delivered" |
| notes | text | | |
| created_at | timestamptz | NOT NULL, default now() | |

### 4.4 ML & System Tables

#### `ml_model_versions`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| version | int | NOT NULL | Auto-increment |
| model_type | text | NOT NULL | "random_forest", "linear_regression" |
| file_path | text | NOT NULL | Path to serialized model file |
| training_start | date | | Date range used for training |
| training_end | date | | |
| mape | numeric | | Evaluation metric |
| r_squared | numeric | | Evaluation metric |
| is_active | boolean | NOT NULL, default false | Which model serves predictions |
| created_at | timestamptz | NOT NULL, default now() | |

Unique: `(version)`.

#### `feature_importance`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| model_version_id | uuid | FK → ml_model_versions.id, NOT NULL | |
| feature_name | text | NOT NULL | e.g. "day_of_week" |
| importance_score | numeric | NOT NULL | 0-1, from Random Forest |
| rank | int | NOT NULL | |

#### `system_logs`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| event_type | text | NOT NULL | "prediction_request", "model_retrain", "api_error", "donation_created" |
| payload | jsonb | | Structured event data |
| severity | text | NOT NULL | "info", "warn", "error" |
| created_at | timestamptz | NOT NULL, default now() | |

---

## 5. Canonical Constants

These are shared across ALL modules. Defined once here.

### 5.1 Bread Categories
```json
[
  { "name": "Croissants",    "display_order": 1, "shelf_life_hours": 24 },
  { "name": "Sweet Bread",   "display_order": 2, "shelf_life_hours": 24 },
  { "name": "Loaves",        "display_order": 3, "shelf_life_hours": 24 },
  { "name": "Ciabatta",      "display_order": 4, "shelf_life_hours": 24 }
]
```

### 5.2 Ingredients (Canonical)
```json
[
  { "name": "Flour",   "unit": "g", "reorder_threshold": 5000  },
  { "name": "Butter",  "unit": "g", "reorder_threshold": 2000  },
  { "name": "Sugar",   "unit": "g", "reorder_threshold": 2000  },
  { "name": "Yeast",   "unit": "g", "reorder_threshold": 200   },
  { "name": "Salt",    "unit": "g", "reorder_threshold": 500   }
]
```

### 5.3 Time Slots
```json
[
  { "slot": "morning",   "start": "06:00", "end": "11:00", "weight_pct": 40 },
  { "slot": "afternoon", "start": "11:00", "end": "15:00", "weight_pct": 35 },
  { "slot": "evening",   "start": "15:00", "end": "18:00", "weight_pct": 25 }
]
```

### 5.4 Weather Conditions (Mapped to Demand Multipliers)
```json
[
  { "condition": "sunny",       "multiplier": 1.10 },
  { "condition": "rainy",       "multiplier": 0.85 },
  { "condition": "cloudy",      "multiplier": 1.00 },
  { "condition": "very_hot",    "multiplier": 0.92 },
  { "condition": "snow",        "multiplier": 0.80 }
]
```

### 5.5 Day-of-Week Multipliers
```json
[
  { "day": "Monday",    "multiplier": 0.95 },
  { "day": "Tuesday",   "multiplier": 0.97 },
  { "day": "Wednesday", "multiplier": 1.02 },
  { "day": "Thursday",  "multiplier": 1.05 },
  { "day": "Friday",    "multiplier": 1.15 },
  { "day": "Saturday",  "multiplier": 1.20 },
  { "day": "Sunday",    "multiplier": 1.08 }
]
```

### 5.6 Season Multipliers
```json
[
  { "season": "spring", "months": [3,4,5],  "multiplier": 1.05 },
  { "season": "summer", "months": [6,7,8],  "multiplier": 0.90 },
  { "season": "autumn", "months": [9,10,11],"multiplier": 1.08 },
  { "season": "winter", "months": [12,1,2], "multiplier": 1.15 }
]
```

---

## 6. Seed Data Strategy

### 6.1 What Needs Seeding

| Dataset | Size | Purpose |
|---|---|---|
| Bakery (1 row) | 1 | Single bakery config |
| Bread categories (4 rows) | 4 | Canonical categories |
| Ingredients (5 rows) | 5 | Canonical ingredients |
| Recipes (4*5 = 20 rows) | 20 | Ingredient per unit per category |
| Charity partners (2-3 rows) | 3 | Default charities |
| Weather records (30 days) | 30 | Historical weather (can use real API or synthetic) |
| Calendar events (30 days) | ~5 | Holidays/events in the range |
| Daily results (30 days, 4 categories) | 120 | Synthetic historical sales for cold-start ML |
| Inventory starting stock | 5 | Initial ingredient levels |

Total seed rows: ~200. All synthetic, generated by a seed script.

### 6.2 Synthetic Historical Data Approach

**30-day bootstrap period:**
- Dates: 30 consecutive days ending "yesterday"
- For each day, generate sales per category using time-slot distribution:
  - Apply day-of-week multiplier to base demand (e.g. 100 * 1.15 for Friday)
  - Apply weather multiplier from weather_records
  - Apply calendar event multiplier if holiday
  - Add gaussian noise (±10%) for realism
  - Record: produced (predicted + 5% buffer), sold, leftover
- This gives the ML model 30 days of "realistic but fake" data to start
- After go-live, real data replaces/grows from this

### 6.3 Seed Script Location

`fyp/backend/supabase/seed/` — a Node.js or Python script that:
1. Reads canonical constants from a shared config file
2. Inserts rows into Supabase
3. Generates synthetic 30-day history
4. Idempotent (can be re-run safely)

---

## 7. Repo Structure

```
fyp/
├── Final Year Project/           # Planning docs (existing)
│   ├── fyp_food_waste.md
│   └── data_foundation/
│       ├── MODULE.md             # High-level plan
│       └── README.md             # Detailed plan
│
├── backend/                      # Node.js middleware
│   └── supabase/
│       ├── schema/
│       │   └── 001_initial.sql   # Full DDL migration
│       ├── seed/
│       │   ├── seed.js           # Seed script
│       │   └── constants.json    # Canonical constants (shared)
│       └── README.md             # Setup instructions
│
├── ml_server/                    # Python FastAPI
│   └── src/
│       └── constants.py          # Same constants, Python format
│
└── flutter_app/                  # Flutter dashboard
    └── lib/
        └── models/               # Dart data classes matching schema
```

---

## 8. Integration Points (How Other Modules Read These Tables)

| Module | Reads Tables | Writes Tables |
|---|---|---|
| Node.js Middleware | ALL (orchestrates queries) | inventory_log, system_logs, donations |
| Python ML Server | daily_results, weather_records, calendar_events, bread_categories | daily_predictions, ml_model_versions, feature_importance |
| POS Simulation | daily_predictions, bread_categories, weather_records, calendar_events | sales_transactions, daily_production, daily_results |
| Leftover Donation | daily_results, charity_partners | donations |
| Flutter Dashboard | daily_predictions, daily_results, inventory, recipes | (none — read only) |
| External API Adapters | — | weather_records, calendar_events |

---

## 9. RLS Policies (Single-Bakery)

Since this is a single bakery with no `bakery_id` scoping, RLS simplifies to:
- All tables: only authenticated users can read/write
- `USING (auth.role() = 'authenticated')`
- No bakery-scoping needed — all data belongs to the one bakery
- Supabase Auth handles user login; `users` table via `auth.users`

---

## 10. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | **Multi-tenant vs single-bakery** | Single-bakery, no `bakery_id` FK | Project scope is one bakery only — simpler schema, fewer joins |
| 2 | **Ingredient unit normalization** | Store everything in grams | Consistent math across modules |
| 3 | **Sales transactions: raw vs pre-aggregated** | Raw transactions (every sale stored) | Enables time-of-day learning, flexible aggregation |
| 4 | **Synthetic seed: deterministic vs random** | Deterministic (seeded PRNG) | Reproducible test data across runs |
| 5 | **Timezone handling** | Store in UTC + bakery.timezone offset | Standard practice, avoids ambiguity |
| 6 | **Supabase local dev vs cloud** | Local Docker for dev | Free, offline, fast iteration, reset anytime |
| 7 | **Migration tool** | Supabase CLI migrations | Standard for Supabase, integrates with local Docker |

---

## 11. Next Steps (Detailed Breakdown)

When we drill into this module, we will produce:
1. **`001_initial.sql`** — full DDL with all CREATE TABLE, indexes, triggers, RLS
2. **`constants.json`** — shared canonical constants file
3. **`seed.js`** — Node.js seed script with synthetic data generation
4. **TypeScript type definitions** — Zod schemas matching DB schema (for Node.js validation)
5. **Python Pydantic models** — mirroring schema (for FastAPI)
6. **Dart data classes** — mirroring schema (for Flutter)

See `README.md` in this folder for the full detailed plan.

---

**Module Status:** High-level plan complete. Ready for detailed breakdown (SQL, seed script, type defs) on your signal.
