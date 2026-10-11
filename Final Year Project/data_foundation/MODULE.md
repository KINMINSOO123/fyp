# Module 0: Data Foundation + Supabase Schema

**Build Order:** 1st (bedrock — all other modules depend on this)
**Status:** High-Level Plan — ready for detailed breakdown

---

## 1. Goal

Define every domain entity, database table, and canonical constant the system shares. One source of truth for schema, types, and seed data so every module (Node.js, Python ML, Flutter) speaks the same language.

**Scope:** Single bakery. No `bakery_id` foreign key on any table. The `bakery_settings` table holds one config row only.

---

## 2. Dependencies

- None. This is the first thing built.

---

## 3. Domain Entities

Every entity that exists in the system (single bakery scope, no multi-tenancy):

| Entity | Description | Table Name |
|---|---|---|
| Bakery Settings | Single bakery config (name, hours, location type) — 1 row | `bakery_settings` |
| User / Staff | Login accounts for dashboard access | `users` (Supabase Auth) |
| Bread Category | Canonical bread types tracked | `bread_categories` |
| Recipe | Per-category ingredient requirements | `recipes` |
| Ingredient | Raw materials tracked in inventory | `ingredients` |
| Inventory Snapshot | Current stock level of each ingredient | `inventory` |
| Inventory Batch | FIFO/expiry stock lots per ingredient | `inventory_batches` |
| Historical Daily Sales | Validated category/day units sold with `DataOrigin` provenance | `daily_sales_records` |
| Daily Prediction | ML output per category per day | `daily_predictions` |
| Production Decision | Manager's selected production option before baking | `production_decisions` |
| Daily Production | What was actually produced per category | `daily_production` |
| Sales Transaction | Individual sale (from POS simulation) | `sales_transactions` |
| Sales Time Slot | Morning / Afternoon / Evening aggregation | `sales_by_timeslot` (VIEW) |
| Completed Simulation Result | Detailed POS simulation result per category/day | `daily_results` |
| Donation Record | Leftover donation to charity | `donations` |
| Waste Record | Manager-confirmed disposal quantity and reason | `waste_records` |
| Charity Partner | Organization receiving donations | `charity_partners` |
| Weather Record | Daily weather snapshot from API | `weather_records` |
| Calendar Event | Holiday / event status from Calendar API | `calendar_events` |
| ML Model Version | Trained model metadata | `ml_model_versions` |
| Model Evaluation | Origin-labelled chronological-holdout metrics | `model_evaluations` |
| Feature Importance | Per-model feature weights | `feature_importance` |
| System Log | Operational audit trail | `system_logs` |
| Notification | Manager-visible alert (low-stock, stock-out, low-confidence, job failure, donation) | `notifications` |
| FCM Token | Per-device push token for Firebase Cloud Messaging | `fcm_tokens` |

---

## 4. Database Schema (Supabase / PostgreSQL)

> **No `bakery_id` FK on any table.** The `bakery_settings` table is a standalone config table with one row. All other tables belong to the single bakery implicitly.

### 4.1 Core Domain Tables

#### `bakery_settings` (config — 1 row only)
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
| selling_price | numeric | NOT NULL, default 0 | Standard retail price per unit (RM). **Reporting only** — never read by prediction/recommendation optimisation. |
| is_active | boolean | NOT NULL, default true | Soft-delete |

Unique: `(name)`.

#### `ingredients`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| name | text | NOT NULL | e.g. "Flour", "Butter", "Sugar", "Yeast", "Salt" |
| unit | text | NOT NULL | **Commercial bulk unit** (e.g. "kg" for flour/butter, "g" for yeast/salt). NOT the storage unit. Recipes remain in `grams_per_unit`; inventory remains in `quantity_grams`. |
| unit_cost | numeric | NOT NULL, default 0 | Cost per bulk `unit` (e.g. RM28.00 per kg of butter). **Reporting only** — never read by prediction/recommendation optimisation. |
| reorder_threshold | numeric | | Alert when stock falls below |

Unique: `(name)`.

> **Unit conversion (finance-only):** ingredient cost per gram = `unit_cost / gramsPerBaseUnit(unit)` where `gramsPerBaseUnit('kg')=1000`, `'g'=1`, `'ml'=1`. Used ONLY by `ingredientCostCalculator` (Module 3 reporting helper). Inventory deduction and recipe math continue to use `grams_per_unit` / `quantity_grams` directly.

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

#### `inventory_batches`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| ingredient_id | uuid | FK → ingredients.id, NOT NULL | |
| received_date | date | NOT NULL | When the batch was added |
| expiry_date | date | NOT NULL | Used for FIFO/FEFO deduction |
| initial_quantity_grams | numeric | NOT NULL | Original batch quantity |
| remaining_quantity_grams | numeric | NOT NULL | Remaining usable quantity |
| source | text | | Optional supplier/source note |
| status | text | NOT NULL, default `active` | `active`, `depleted`, `expired`, `discarded` |
| created_at | timestamptz | NOT NULL, default now() | |

Indexes: `(ingredient_id, expiry_date, received_date)`, `(status, expiry_date)`.

**FIFO rule:** production deduction consumes the oldest non-expired active batch first, ordered by `expiry_date`, then `received_date`. The `inventory.quantity_grams` row remains a cached total for fast dashboard/low-stock checks and is updated whenever batches change.

#### `inventory_log`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| inventory_id | uuid | FK → inventory.id | |
| batch_id | uuid | FK → inventory_batches.id | Optional; filled when a specific FIFO batch is affected |
| change_grams | numeric | NOT NULL | Positive = restock, negative = used |
| reason | text | NOT NULL | "daily_production", "manual_restock", "spoilage" |
| effective_date | date | NOT NULL | Business date of the movement; used to reconstruct stock for historical as-of reruns |
| created_at | timestamptz | NOT NULL, default now() |

#### `notifications`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK, default gen_random_uuid() | |
| type | text | NOT NULL | `stock_out` \| `low_stock` \| `low_confidence` \| `prediction_reminder` \| `simulation_reminder` \| `donation_completed` |
| severity | text | NOT NULL | `info` \| `warning` \| `critical` |
| title | text | NOT NULL | Short alert title |
| message | text | NOT NULL | Human-readable body |
| related_id | uuid | NULL | Polymorphic FK: ingredient_id, prediction_id, donation_id; NULL for reminder-only notifications |
| is_read | boolean | NOT NULL, default false | Set true when user dismisses |
| created_at | timestamptz | NOT NULL, default now() | |

Index: `(is_read, created_at DESC)` — dashboard unread-first listing.
RLS: realtime publication enabled (for Flutter live subscription).

#### `fcm_tokens`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK, default gen_random_uuid() | |
| user_id | uuid | FK → auth.users.id, NOT NULL | Which staff account this device belongs to |
| token | text | NOT NULL, UNIQUE | Firebase Cloud Messaging device token |
| device_info | text | NULL | Optional label (e.g. "Pixel 7", "iPad") |
| created_at | timestamptz | NOT NULL, default now() | |
| updated_at | timestamptz | NOT NULL, default now() | |

Notes:
- One user may have multiple rows (logged in on phone + tablet) — `sendEachMulticast` broadcasts to all.
- On logout, Flutter calls `DELETE /api/fcm/unregister` so former staff stop receiving alerts.
- Firebase rotates tokens periodically → Flutter's `onTokenRefresh` re-registers via `POST /api/fcm/register`.

### 4.2 Prediction & Results Tables

#### `daily_sales_records`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| sales_date | date | NOT NULL | Observation date |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| units_sold | int | NOT NULL, CHECK >= 0 | Current prediction/training target |
| data_origin | text | NOT NULL, CHECK allowed values | `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL`, `SIMULATION_GENERATED` |
| is_validated | boolean | NOT NULL, default false | Only validated rows are suitable for ML |
| source_reference_id | uuid | NULL | For simulation rows, references the source `daily_results.id`; import/actual provenance may use an external reference |
| validation_notes | text | NULL | |
| created_at | timestamptz | NOT NULL, default now() | |

Unique: `(sales_date, bread_category_id, data_origin, source_reference_id)`.

`DailySalesRecord` is the only canonical historical-sales record used by prediction, training and evaluation. A successful POS simulation creates one validated row per category with `data_origin = SIMULATION_GENERATED`. Simulation-generated rows may be used for development training, but any evaluation containing them must be labelled simulation-based and not presented as real-world accuracy.

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
| predicted_units_sold | int | NOT NULL | Units predicted to be sold |
| confidence | numeric | NOT NULL, CHECK 0-100 | Model confidence/stability score |
| model_version_id | uuid | FK → ml_model_versions.id | Which model made this |
| weather_record_id | uuid | FK → weather_records.id | Weather data used |
| created_at | timestamptz | NOT NULL, default now() | |

Unique: `(target_date, bread_category_id)`.

#### `production_decisions`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| target_date | date | NOT NULL | Production date being decided |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| prediction_id | uuid | FK → daily_predictions.id | Prediction used for decision |
| predicted_units_sold | int | NOT NULL | Snapshot from ML output |
| recommended_production | int | NOT NULL | Snapshot after inventory/recipe constraints |
| max_producible | int | NOT NULL | Feasibility limit calculated from recipe + inventory at confirmation time |
| final_selected_qty | int | NOT NULL | Manager-approved quantity to bake |
| selected_option | text | NOT NULL | `full_prediction`, `reduced_due_constraint`, `manual_override` |
| decision_reason | text | Required unless `selected_option = full_prediction` | e.g. "yeast shortage", "staff shortage", "manager override" |
| confirmed_by | uuid | FK → auth.users.id | Manager account that confirmed the decision |
| confirmed_at | timestamptz | NOT NULL, default now() | Confirmation time |
| created_at | timestamptz | NOT NULL, default now() | |
| updated_at | timestamptz | NOT NULL, default now() | |

Unique: `(target_date, bread_category_id)`.

Rules:
- `final_selected_qty` must be between 0 and `max_producible`.
- `full_prediction` means the final quantity matches `recommended_production`.
- `reduced_due_constraint` means the final quantity is lower than `recommended_production`.
- A reason is required for `reduced_due_constraint` and `manual_override`.
- Confirming a production decision does not deduct inventory; inventory is deducted only when production/simulation is recorded.
- Each confirmation/update writes an audit event to `system_logs`.

#### `daily_production`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| production_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | |
| production_decision_id | uuid | FK → production_decisions.id | Links to manager decision, if recorded |
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
| units_sold | int | NOT NULL | Sum from sales_transactions |
| leftover | int | NOT NULL | produced - sold |
| remaining_unallocated_leftover | int | NOT NULL | leftover - confirmed donations - confirmed waste |
| estimated_demand | int | | units_sold + lost_sales; analysis only |
| lost_sales | int | DEFAULT 0 | max(0, estimated_demand - produced) when stock-out occurs |
| waste_rate_pct | numeric | | (leftover / produced) * 100 |
| error_units | int | | produced - sold |
| error_pct | numeric | | prediction accuracy |
| notes | text | | Optional manual correction / stock-out note |

Unique: `(result_date, bread_category_id)`.

**Column relationships (after POS simulation):**
```
estimated_demand = units_sold + lost_sales              ← analysis only, not ML target
units_sold       ≤ produced                              ← capped at production
leftover         = produced - units_sold                ← always ≥ 0
remaining_unallocated_leftover = leftover - donated - wasted
waste_rate   = (leftover / produced) × 100
error_pct    = |predicted_units_sold - units_sold| / units_sold × 100
```

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
| daily_result_id | uuid | FK → daily_results.id, NOT NULL | Source leftover allocation |
| charity_partner_id | uuid | FK → charity_partners.id, NOT NULL | |
| donation_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | Donation is category-specific |
| quantity | int | NOT NULL | |
| status | text | NOT NULL | "recorded", "picked_up", "delivered" |
| confirmed_by | uuid | FK → auth.users.id, NOT NULL | Bakery Manager who confirmed |
| notes | text | | |
| created_at | timestamptz | NOT NULL, default now() | |

The system may recommend a donation, but it must not insert this row until the Bakery Manager confirms it.

#### `waste_records`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| daily_result_id | uuid | FK → daily_results.id, NOT NULL | Source leftover allocation |
| waste_date | date | NOT NULL | |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | Waste is category-specific |
| quantity | int | NOT NULL, CHECK > 0 | |
| disposal_reason | text | NOT NULL | Required reason |
| confirmed_by | uuid | FK → auth.users.id, NOT NULL | Bakery Manager who confirmed |
| created_at | timestamptz | NOT NULL, default now() | |

Donation plus waste for a result/category must not exceed `daily_results.leftover`; updates maintain `remaining_unallocated_leftover`. The service executes the allocation validation and related writes transactionally through Node.js Repos.

### 4.4 ML & System Tables

#### `ml_model_versions`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| version | int | NOT NULL | Auto-increment |
| bread_category_id | uuid | FK → bread_categories.id, NOT NULL | One model row per category |
| model_type | text | NOT NULL | "random_forest", "linear_regression" |
| file_path | text | NOT NULL | Path to serialized model file |
| training_start | date | | Date range used for training |
| training_end | date | | |
| lifecycle_status | text | NOT NULL, default `candidate` | `candidate`, `active`, `inactive`, `rejected` |
| activated_by | uuid | FK → auth.users.id | Administrator |
| activated_at | timestamptz | NULL | |
| created_at | timestamptz | NOT NULL, default now() | |

Unique: `(version, bread_category_id)`.

Retraining always creates a candidate. Only the System Administrator may activate an evaluated candidate or restore a previous valid inactive version. At most one model version per category is active.

#### `model_evaluations`
| Column | Type | Constraint | Notes |
|---|---|---|---|
| id | uuid | PK | |
| model_version_id | uuid | FK → ml_model_versions.id, NOT NULL | Candidate/existing version evaluated |
| holdout_start | date | NOT NULL | Chronologically later than the training period |
| holdout_end | date | NOT NULL | |
| data_origins | text[] | NOT NULL | Origins present in holdout rows |
| evaluation_label | text | NOT NULL | Explicitly identifies real/imported/simulation-based/mixed evidence |
| mae | numeric | NOT NULL | Includes zero-actual observations |
| rmse | numeric | NOT NULL | Includes zero-actual observations |
| mape | numeric | NULL | Excludes only zero-actual observations |
| r_squared | numeric | NULL | |
| sample_count | int | NOT NULL | All holdout rows |
| mape_sample_count | int | NOT NULL | Non-zero-actual rows used by MAPE |
| evaluated_at | timestamptz | NOT NULL, default now() | |

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
| event_type | text | NOT NULL | "prediction_request", "model_retrain", "operation_reminder_sent", "api_error", "donation_created" |
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

### 5.6 Monsoon Season Multipliers (Malaysia)
```json
[
  { "season": "northeast_monsoon", "months": [11,12,1,2,3], "multiplier": 0.90 },
  { "season": "inter_monsoon",     "months": [4,10],        "multiplier": 0.98 },
  { "season": "southwest_monsoon", "months": [5,6,7,8,9],   "multiplier": 1.05 }
]
```

### 5.7 Configurable Prediction Controls

- `minimum_training_days = 30`
- `low_confidence_threshold_pct = 75`
- Cold-start base units per bread category
- Cold-start weather, holiday, weekday and seasonal adjustment factors

These are initial configurable values, not hard-coded formulas. The final confidence formula remains subject to approval; Random Forest tree variance/model agreement is the planned basis.

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
| Weather records (90 days) | 90 | Historical weather (can use real API or synthetic) |
| Calendar events (90 days) | ~10-15 | Holidays/events in the range |
| Daily sales records (90 days, 4 categories) | 360 | Synthetic development history marked `SIMULATION_GENERATED` |
| Daily results (90 days, 4 categories) | 360 | Detailed synthetic simulation outcomes linked to the generated history |
| Production decisions (90 days, 4 categories) | 360 | Synthetic manager decisions for POS simulation |
| Inventory starting stock | 5 | Initial ingredient snapshot totals |
| Inventory starting batches | 5-10 | FIFO lots behind the inventory snapshot |

Total seed rows: ~505+ plus generated sales transactions. All synthetic, generated by a seed script.

### 6.2 Synthetic Historical Data Approach

**90-day bootstrap period:**
- Dates: 90 consecutive days ending "yesterday"
- For each day, generate sales per category using time-slot distribution:
  - Apply day-of-week multiplier to base demand (e.g. 100 * 1.15 for Friday)
  - Apply weather multiplier from weather_records
  - Apply calendar event multiplier if holiday
  - Add gaussian noise (±10%) for realism
  - Record: produced (predicted + 5% buffer), sold, leftover
- This gives the ML model enough "realistic but fake" data for weekday/weather evaluation while keeping the FYP seed manageable
- Each synthetic category/day result produces a validated `daily_sales_records` row with `data_origin = SIMULATION_GENERATED`
- Development evaluation on these records is labelled simulation-based; it is not reported as real-world accuracy
- After go-live, `ACTUAL_TRANSACTION` and validated `IMPORTED_HISTORICAL` records provide real/imported evidence without overwriting provenance

### 6.3 Seed Script Location

`fyp/backend/supabase/seed/` — a Node.js script that:
1. Reads canonical constants from a shared config file
2. Inserts rows into Supabase
3. Generates synthetic 90-day history
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
| Node.js/Express through TypeScript Repos | ALL application tables | All application tables according to service rules |
| Python FastAPI ML Server | None directly; receives validated DTOs from TypeScript | None directly; returns prediction/training/evaluation DTOs |
| POS Simulation TypeScript Services | daily_predictions, production_decisions, bread_categories and traceability context through Repos | sales_transactions, daily_production, daily_results, daily_sales_records through Repos |
| Leftover Management TypeScript Services | daily_results, charity_partners, donations, waste_records through Repos | donations, waste_records and remaining allocation through Repos |
| Flutter Views | No PostgreSQL tables directly; use Express APIs | No PostgreSQL tables directly |
| External API Adapters | No tables directly | Return provider data to ContextService, which caches through Repos |

---

## 9. RLS and Database-Access Policy (Single Bakery)

- Supabase Authentication handles login/session issuance through its authentication API.
- Flutter does not receive direct CRUD policies for application tables.
- Node.js/Express is the sole application-database owner and accesses PostgreSQL through TypeScript Repos using protected server credentials.
- FastAPI has no Supabase credentials.
- RLS remains enabled as defence in depth; direct `authenticated` client CRUD on application tables is denied unless a narrowly scoped future requirement is explicitly approved.
- No bakery-scoping predicate is needed because all data belongs to the single bakery.

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
| 8 | **Background push mechanism** | Firebase Cloud Messaging (FCM) through a Node.js external-service adapter | Required for staff phones to receive alerts when the app is closed/backgrounded. Node reads device tokens through `FcmTokenRepo` and broadcasts without exposing database access to Flutter or FastAPI. |
| 9 | **Foreground live updates** | Authenticated Node.js API plus optional SSE/WebSocket relay | Updates the Flutter bell badge while the app is open. Node may observe relevant database changes internally, but Flutter never subscribes to a Supabase table directly. Hybrid delivery remains Node foreground delivery + FCM background push. |
| 10 | **Notification dedupe** | Skip emit if unread alert of same `type + related_id` exists | Prevents alert spam (e.g. repeated low-stock for same ingredient). Once read, a new occurrence can alert again. |
| 11 | **FIFO inventory** | Lightweight batch tracking with expiry dates | Realistic for perishable bakery ingredients while still feasible for an FYP. `inventory` stores totals; `inventory_batches` stores the FIFO lots. |

---

## 11. Next Steps (Detailed Breakdown)

When we drill into this module, we will produce:
1. **`001_initial.sql`** — full DDL with all CREATE TABLE, indexes, triggers, RLS
2. **`constants.json`** — shared canonical constants file
3. **`seed.js`** — Node.js seed script with synthetic data generation
4. **TypeScript type definitions** — Zod schemas matching DB schema (for Node.js validation)
5. **Python Pydantic models** — only the versioned prediction/training/evaluation API DTOs required by FastAPI, not database-row models
6. **Dart data classes** — API response/request models needed by Flutter Views, not direct database bindings

See `README.md` in this folder for the full detailed plan.

---

**Module Status:** High-level plan complete. Ready for detailed breakdown (SQL, seed script, type defs) on your signal.
