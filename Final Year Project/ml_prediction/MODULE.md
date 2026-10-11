# Module 2: ML Server + Core Prediction

**Build Order:** 3rd (depends on Module 0: Data Foundation, Module 1: Node.js Middleware)
**Status:** High-Level Plan — ready for detailed breakdown
**Architecture:** Validated DTO → thin FastAPI route module → Python Service → model/artifact component (see `../ARCHITECTURE.md`)

> **Revised boundary:** FastAPI has no Supabase client or application Repos. Node.js/Express supplies validated `DailySalesRecord` and contextual DTOs through `FastApiMlClient`; FastAPI returns prediction, candidate-training and origin-labelled evaluation results.

---

## 1. Goal

Build the Python FastAPI ML server that predicts next-day bread demand per category using Random Forest (primary) + Linear Regression (baseline), with manual/admin retraining and feature importance analysis.

This is the **HEART** of the system (master doc §4.1, §6). Everything else supports this module.

---

## 2. Dependencies

- **Module 0 (Data Foundation)** — defines the language-neutral prediction/training/evaluation DTO contract and configurable constants
- **Module 1 (Node.js Middleware)** — validates `DailySalesRecord`/context data, calls this server through `FastApiMlClient`, and owns all database persistence

---

## 3. Sub-Modules

| # | Sub-Module | Layer | Purpose |
|---|---|---|---|
| 2.1 | FastAPI App Skeleton | — | App setup, server entry, config |
| 2.2 | Contract Models | DTO | Pydantic request/result models shared semantically with TypeScript |
| 2.3 | Feature Preparation Service | Service | Builds prediction/training feature matrices from supplied observations; target is `unitsSold` |
| 2.4 | Model Training Service | Service | Trains Random Forest + Linear Regression candidates from administrator-supplied validated data |
| 2.5 | Prediction Service | Service | Selects active-artifact or cold-start flow from the supplied request |
| 2.6 | Training Route Module | Module | Thin `POST /train` endpoint delegates to `ModelTrainingService` |
| 2.7 | Prediction Route Module | Module | Thin `POST /predict` endpoint delegates to `PredictionService` |
| 2.8 | Evaluation Service | Service | MAE, RMSE, MAPE, R² (pure calculations) |
| 2.9 | Model Persistence | — | Save/load joblib files (file I/O, not DB) |
| 2.10 | Feature Importance | Service | RF feature weights returned to TypeScript; no DB write |
| 2.11 | Confidence Service | Service | Dedicated tree-variance/model-agreement planning boundary; final formula unapproved |
| 2.12 | Cold-Start Service | Service | Configurable heuristic when fewer than 30 suitable records are supplied |
| 2.13 | Model Artifact Store | Infrastructure | Save/load versioned estimator files; not a database Repo |

---

## 4. Resolved Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Model architecture | One model per category (4 RF models) | Each specializes in its category's patterns; matches master doc's per-category output |
| 2 | Confidence calculation | Dedicated `ConfidenceService`; RF tree variance/model agreement is the planned basis | The final mathematical formula is not yet approved. Low-confidence threshold is configurable, initially 75%; the result is not a probability guarantee. |
| 3 | Dependency management | `requirements.txt` | Simplest, universal, no extra tooling; good for FYP |
| 4 | Cold-start (<30 suitable records/days) | `ColdStartService` with configurable base units and contextual adjustment factors | Predictions remain available without hard-coding constants into service logic; trained-model mode begins only with sufficient suitable history and an active artifact. |
| 5 | **Training target** | `DailySalesRecord.unitsSold` | `lostSales` and `estimatedDemand` remain analysis fields. Each observation retains `DataOrigin`; simulation-generated rows may support development training but simulation-based evaluation is never presented as real-world accuracy. |
| 6 | Seed history | 90 days generated, 30 days minimum for RF | 90 days gives enough weekday/weather variety for evaluation; 30 days remains the minimum threshold before switching from heuristic mode. |
| 7 | Inventory constraints | Module 3 only | ML predicts raw expected sales. Recipes, ingredient shortages, and max producible logic are applied by the Node.js recommendation engine after prediction. |
| 8 | Model lifecycle | Retraining creates a candidate; evaluation precedes System Administrator activation; previous valid versions can be restored | FastAPI returns artifacts/results, while Node.js owns lifecycle persistence and activation through Repos. |
| 9 | Evaluation split | Chronologically later holdout observations | Prevents future-to-past leakage. MAE/RMSE retain zero actuals; MAPE alone excludes them. Results include MAE, RMSE, MAPE, R² and an origin label. |

---

## 5. API Endpoints (called by Node.js)

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Health check |
| POST | `/predict` | Predict demand for a date (all 4 categories) |
| POST | `/train` | Train candidate models from validated observations supplied by TypeScript |
| POST | `/evaluate` | Evaluate specified artifacts on supplied chronological holdout observations |

Active-version queries, activation, restoration and feature-importance persistence are Node.js responsibilities. FastAPI route functions are thin module-level endpoints and are not UML Controller classes.

---

## 6. Model Architecture (4 models, one per category)

```
For each bread category (Croissants, Sweet Bread, Loaves, Ciabatta):
  ├─ Random Forest Regressor (primary)
  │   ├─ n_estimators=100, random_state=42
  │   ├─ Outputs: predictedUnitsSold + confidence/model-agreement indicator
  │   └─ Provides feature_importance for explainability
  │
  └─ Linear Regression (baseline, for comparison)
      └─ Outputs: predictedUnitsSold (baseline comparison)

Training data: validated TrainingObservation DTOs assembled by TypeScript from DailySalesRecord + context
Target variable: unitsSold
Features: 14 engineered features (see Section 7)

Model selection: RF is primary (serves predictions);
LR kept for baseline comparison in evaluation reports. Trained outputs remain candidates until Node.js records a valid evaluation and a System Administrator activates them.
```

---

## 7. Input Features (14 per row, from §4.1.2)

### Category A: Historical (5 features)
| Feature | Description |
|---|---|
| `rolling_avg_30d` | Prior 30-day rolling avg sales for this category |
| `rolling_avg_7d` | Prior 7-day rolling avg sales |
| `same_weekday_avg` | Prior avg sales on same day-of-week (last 4 matching days) |
| `trend_7d` | Slope of prior 7 days sales |
| `yesterday_demand` | Previous day's actual sales |

### Category B: Temporal (4 features)
| Feature | Description |
|---|---|
| `day_of_week` | 1-7 (Mon-Sun) |
| `month` | 1-12 |
| `monsoon_season` | 0=northeast, 1=inter, 2=southwest |
| `week_of_year` | 1-52 |

### Category C: External (5 features)
| Feature | Description |
|---|---|
| `weather_sunny` | One-hot (0/1) |
| `weather_rainy` | One-hot (0/1) |
| `temp_high_c` | Numeric (Celsius) |
| `is_holiday` | 0/1 |
| `holiday_multiplier` | 1.0 / 1.30 / 0.90 etc. |

**Not ML features:** inventory levels, recipes, and `max_producible` are handled by Module 3 after ML prediction. This keeps the ML target as raw expected sales and avoids mixing demand forecasting with production feasibility.

---

## 8. Confidence / Stability Score (RF tree variance)

`ConfidenceService` remains a dedicated class. Random Forest tree variance/model agreement is the planned evidence: lower dispersion among tree predictions indicates stronger agreement. The final mapping to a 0–100 indicator is unresolved and must not be invented in implementation until approved. The low-confidence threshold is configurable and initially `75%`. Confidence is an advisory model-agreement indicator, not the probability that the exact demand will occur.

---

## 9. Cold-Start Fallback (<30 days data)

```
IF suitable DailySalesRecord count < 30:
  ColdStartService uses configured values supplied by the application:

  for each category:
    base      = base_daily_demand[category]       # e.g. 100
    dow_mult  = dow_multipliers[day_name]         # e.g. 1.15 (Friday)
    weather   = weather_multipliers[condition]    # e.g. 1.10 (sunny)
    season    = monsoon_multiplier[season]        # e.g. 1.05
    holiday   = holiday_multiplier or 1.0         # e.g. 1.30

    predicted = base × dow × weather × season × holiday
    confidence/stability = configured cold-start indicator

  No model training, no feature importance.
  Once 30+ suitable records exist → an administrator may train a candidate;
  the RF serves predictions only after evaluation and administrator activation.
```

---

## 10. File Structure

> Follows the FastAPI boundary in `../ARCHITECTURE.md`: contract DTO → thin route module → Python Service → model/artifact component.

```
ml_server/
├── src/
│   ├── app.py                      # FastAPI app setup
│   ├── server.py                   # Entry point (uvicorn)
│   ├── config/
│   │   └── env.py                  # Model/artifact settings only; no Supabase credentials
│   ├── contracts/                  # Pydantic prediction/training/evaluation DTOs
│   ├── services/
│   │   ├── prediction_service.py
│   │   ├── feature_preparation_service.py
│   │   ├── model_training_service.py
│   │   ├── model_evaluation_service.py
│   │   ├── confidence_service.py
│   │   └── cold_start_service.py
│   ├── infrastructure/
│   │   └── model_artifact_store.py # Save/load joblib files; not a database Repo
│   ├── models/
│   │   └── category_predictor.py
│   ├── routes/                     # Thin module-level FastAPI endpoints
│   │   ├── prediction_routes.py
│   │   ├── training_routes.py
│   │   └── evaluation_routes.py
│   └── utils/
│       └── logger.py
├── models/                         # Saved joblib model files (file storage)
│   ├── croissants_rf_v1.joblib
│   ├── croissants_lr_v1.joblib
│   ├── sweet_bread_rf_v1.joblib
│   └── ...
├── requirements.txt
├── .env.example
└── README.md
```

**Note:** There is deliberately no FastAPI `repositories/` package or Supabase client. `ModelArtifactStore` persists model files only.

---

## 11. Environment Variables (`.env.example`)

```
MODEL_DIR=./models
MIN_TRAINING_DAYS=30
RF_N_ESTIMATORS=100
RF_RANDOM_STATE=42
TEST_SPLIT_RATIO=0.2
LOW_CONFIDENCE_THRESHOLD=75
```

---

## 12. Integration Points

| Talks To | Direction | Protocol |
|---|---|---|
| Node.js Middleware | Incoming | HTTP REST (JSON) — called by orchestrator |
| Disk (joblib files) | Outgoing | File I/O — model persistence |

**Tables read/written by FastAPI:** none. TypeScript persists all application records through Repos.

---

## 13. Evaluation Targets (from master doc §6)

| Metric | Target | Notes |
|---|---|---|
| MAE | Reported | Includes zero-actual observations |
| RMSE | Reported | Includes zero-actual observations |
| MAPE | < 10% planning target | Excludes only zero-actual observations; records `mapeSampleCount` |
| R² | > 0.85 | Explains 85%+ of demand variance |

Evaluation uses chronologically later holdout observations and carries their `DataOrigin` values. Results containing `SIMULATION_GENERATED` observations are explicitly labelled simulation-based and are not described as real-world accuracy.

---

## 14. What This Module Does NOT Include

- ❌ Fetching weather/calendar from external APIs → Module 1 fetches and caches context first; Python reads cached rows for the requested `target_date`
- ❌ Inventory constraint adjustment → Module 3 (Node.js post-processes prediction)
- ❌ POS simulation generating training data → Module 4
- ❌ Database access or model activation → Node.js/Express owns both application persistence and administrator activation
- ❌ Automatic nightly retraining → out of prototype scope; System Administrator training is manual and produces candidates

---

## 15. Next Steps (Detailed Breakdown)

See `README.md` in this folder for the detailed plan (function signatures, feature engineering logic, training pipeline, API request/response schemas, verification).

---

**Module Status:** High-level plan complete. Ready for detailed breakdown on your signal.
