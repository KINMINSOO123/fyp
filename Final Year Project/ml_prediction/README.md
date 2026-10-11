# Module 2: ML Server + Core Prediction — Detailed Plan

**Build Order:** 3rd (depends on Module 0: Data Foundation, Module 1: Node.js Middleware)
**Status:** Detailed plan — ready for implementation
**Architecture:** Validated DTO → thin FastAPI route module → Python Service → model/artifact component (see `../ARCHITECTURE.md`)

> See `MODULE.md` in this folder for the high-level plan (sub-modules, model architecture, feature list, file structure).
> This README documents the concrete artifacts to build: repo queries, service logic, feature engineering, training pipeline, API schemas, verification.

## Revision baseline (authoritative)

This detailed plan predates the revised database boundary. The following rules supersede every conflicting Supabase/repository/controller snippet later in this file:

- FastAPI has no Supabase configuration, client, application Repo or database-row model. Delete the planned Python repository artifacts; do not implement their sketches.
- Node.js `PredictionOrchestrationService` and `ModelManagementService` query `DailySalesRecordRepo`/context Repos, validate data, and call `FastApiMlClient`.
- FastAPI contains thin route modules plus `PredictionService`, `FeaturePreparationService`, `ModelTrainingService`, `ModelEvaluationService`, `ConfidenceService`, `ColdStartService`, `CategoryPredictor` and `ModelArtifactStore`.
- Training/evaluation target is `DailySalesRecord.unitsSold`; observations carry `ACTUAL_TRANSACTION`, `IMPORTED_HISTORICAL` or `SIMULATION_GENERATED`.
- Administrator-triggered training creates candidate artifacts. Chronologically later holdout evaluation returns MAE, RMSE, MAPE and R²; zero actuals remain in MAE/RMSE and are excluded only from MAPE. Evaluation is labelled by origin.
- Candidates become active only after explicit System Administrator activation in Node.js; a previous valid model can be restored.
- `ConfidenceService` retains Random Forest tree variance/model agreement as its planned basis, but the final formula is unresolved. The configurable low-confidence threshold starts at 75%.
- `ColdStartService` is used with fewer than 30 suitable records; its base values and contextual factors are configurable.

Sections containing old `trainingDataRepo`, `predictionRepo`, direct Supabase calls, direct persistence, automatic activation, random split, fixed confidence formula or `/retrain` behaviour are retained only as historical sketches and must not be implemented.

---

## 1. Dependencies (from Modules 0 & 1)

| Artifact | Used For |
|---|---|
| `ml_server/src/models.py` (from Module 0) | Pydantic models mirroring DB schema (Model layer) |
| Supabase schema tables | `daily_results`, `weather_records`, `calendar_events`, `bread_categories`, `daily_predictions`, `ml_model_versions`, `feature_importance` |
| `backend/supabase/seed/constants.json` (from Module 0) | Multipliers for cold-start fallback |
| Node.js Middleware (Module 1) | Calls this server's endpoints via `ML_SERVER_URL` |

---

## 2. Artifacts to Build

> FastAPI has no application Repo layer. Pydantic validates boundary DTOs; route modules delegate to Python service classes; `ModelArtifactStore` handles model files.

| # | Path | Layer | Purpose |
|---|---|---|---|
| 1 | `ml_server/requirements.txt` | — | Python dependencies |
| 2 | `ml_server/.env.example` | — | Env var template |
| 3 | `ml_server/src/app.py` | — | FastAPI app setup |
| 4 | `ml_server/src/server.py` | — | Entry point (uvicorn) |
| 5 | `ml_server/src/config/env.py` | — | Pydantic-settings env config |
| 6 | `ml_server/src/contracts/*.py` | DTO | Prediction/training/evaluation Pydantic contracts |
| 7 | `ml_server/src/services/feature_preparation_service.py` | Service | Canonical feature preparation |
| 8 | `ml_server/src/services/prediction_service.py` | Service | Active-artifact or cold-start prediction orchestration |
| 9 | `ml_server/src/services/model_training_service.py` | Service | Candidate training |
| 10 | `ml_server/src/services/model_evaluation_service.py` | Service | Chronological, origin-labelled MAE/RMSE/MAPE/R² |
| 11 | `ml_server/src/services/confidence_service.py` | Service | Dedicated model-agreement boundary; final formula pending |
| 12 | `ml_server/src/services/cold_start_service.py` | Service | Configurable fallback under 30 suitable records |
| 13 | `ml_server/src/models/category_predictor.py` | Model wrapper | RF primary + LR baseline per category |
| 14 | `ml_server/src/infrastructure/model_artifact_store.py` | Infrastructure | Save/load candidate and active joblib artifacts |
| 15 | `ml_server/src/routes/prediction_routes.py` | Module | Thin `/predict` route |
| 16 | `ml_server/src/routes/training_routes.py` | Module | Thin `/train` route |
| 17 | `ml_server/src/routes/evaluation_routes.py` | Module | Thin `/evaluate` route |
| 18 | `ml_server/src/utils/logger.py` | — | Logging utility |
| 19 | `ml_server/models/` | — | Directory for saved joblib files |

### 2.1 Canonical service and lifecycle flow

```text
PredictionOrchestrationService (TypeScript)
  -> DailySalesRecordRepo + ContextService + ModelVersionRepo
  -> validates and creates PredictionRequest
  -> FastApiMlClient
  -> POST /predict (thin FastAPI route)
  -> PredictionService
       -> if suitable history < 30 or no active artifact: ColdStartService
       -> otherwise: FeaturePreparationService + CategoryPredictor + ConfidenceService
  <- PredictionResponse
  -> DailyPredictionRepo persists results

ModelManagementService (TypeScript, System Administrator)
  -> validated DailySalesRecord/context observations
  -> POST /train -> ModelTrainingService -> candidate TrainingResult
  -> POST /evaluate with chronologically later holdout -> ModelEvaluationService
  <- MAE, RMSE, MAPE, R² + DataOrigin label
  -> TypeScript Repos persist candidate/evaluation/feature importance
  -> administrator explicitly activates candidate or restores previous valid version
```

MAPE alone filters observations whose actual `unitsSold` is zero; MAE and RMSE use the complete holdout. Any holdout containing `SIMULATION_GENERATED` data is labelled simulation-based.

---

## 3. Dependencies (`requirements.txt`)

```
fastapi==0.111.0
uvicorn[standard]==0.29.0
scikit-learn==1.4.2
pandas==2.2.0
numpy==1.26.4
joblib==1.4.2
supabase==2.4.0
pydantic==2.7.0
pydantic-settings==2.2.0
python-dotenv==1.0.1
httpx==0.27.0
```

---

## 4. Config Layer

### 4.1 `src/config/env.py`
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    MODEL_DIR: str = "./models"
    MIN_TRAINING_DAYS: int = 30
    RF_N_ESTIMATORS: int = 100
    RF_RANDOM_STATE: int = 42
    TEST_SPLIT_RATIO: float = 0.2

    class Config:
        env_file = ".env"

settings = Settings()
```

### 4.2 `[RETIRED — DO NOT IMPLEMENT] src/config/supabase.py`
```python
from supabase import create_client
from .env import settings

supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
```

---

## 5. Constants Loader (`src/features/constants.py`)

Loads `constants.json` (shared from Module 0) for cold-start heuristic predictions.

```python
import json
from pathlib import Path

def load_constants() -> dict:
    """Load constants.json shared from Module 0.
    Expected location: backend/supabase/seed/constants.json
    """
    paths = [
        Path("../backend/supabase/seed/constants.json"),
        Path("../../backend/supabase/seed/constants.json"),
        Path("constants.json"),
    ]
    for p in paths:
        if p.exists():
            return json.loads(p.read_text())
    raise FileNotFoundError("constants.json not found")

def get_season_multiplier(constants: dict, month: int) -> float:
    """Map month → monsoon season multiplier."""
    for season in constants["season_multipliers"]:
        if month in season["months"]:
            return season["multiplier"]
    return 1.0
```

---

## 6. `[RETIRED — DO NOT IMPLEMENT]` Python Supabase Repositories

> Repos do ONLY Supabase queries. No business logic, no model training. See `../ARCHITECTURE.md` §4.2.

### 6.1 `src/repositories/trainingDataRepo.py`

```python
import pandas as pd
from ..config.supabase import supabase

async def fetch_training_data(category_id: str) -> pd.DataFrame:
    """Fetch daily_results, weather, and calendar for a category.

    The Supabase Python client can be awkward for date-based nested joins, so
    fetch each table separately and merge in pandas. The ML target remains
    `sold`; `lost_sales` is retained only for stock-out reporting.
    """
    results = supabase.table("daily_results").select(
        "result_date, bread_category_id, sold, lost_sales, produced, predicted"
    ).eq("bread_category_id", category_id).order("result_date").execute()

    df = pd.DataFrame(results.data)
    if df.empty:
        return df

    df = df.rename(columns={"result_date": "date"})
    df["date"] = pd.to_datetime(df["date"])

    start = df["date"].min().date().isoformat()
    end = df["date"].max().date().isoformat()

    weather = supabase.table("weather_records").select(
        "date, condition, temp_high_c"
    ).gte("date", start).lte("date", end).execute()
    weather_df = pd.DataFrame(weather.data)
    if not weather_df.empty:
        weather_df["date"] = pd.to_datetime(weather_df["date"])
        df = df.merge(weather_df, on="date", how="left")

    calendar = supabase.table("calendar_events").select(
        "date, demand_multiplier"
    ).gte("date", start).lte("date", end).execute()
    calendar_df = pd.DataFrame(calendar.data)
    if not calendar_df.empty:
        calendar_df["date"] = pd.to_datetime(calendar_df["date"])
        calendar_df = calendar_df.groupby("date", as_index=False).agg(
            holiday_multiplier=("demand_multiplier", "max")
        )
        df = df.merge(calendar_df, on="date", how="left")

    df["lost_sales"] = df["lost_sales"].fillna(0)
    df["condition"] = df["condition"].fillna("cloudy")
    df["temp_high_c"] = df["temp_high_c"].fillna(28)
    df["holiday_multiplier"] = df["holiday_multiplier"].fillna(1.0)
    df["is_holiday"] = (df["holiday_multiplier"] != 1.0).astype(int)
    df["day_of_week"] = df["date"].dt.dayofweek + 1  # 1=Mon
    df["month"] = df["date"].dt.month
    df["week_of_year"] = df["date"].dt.isocalendar().week
    return df
```

### 6.2 `src/repositories/predictionRepo.py`
```python
async def fetch_prediction_context(target_date: str) -> dict:
    """Fetch weather + calendar for a target date (for prediction, not training).

    Node.js owns external API calls. For normal flow, Node.js calls its context
    service first so weather/calendar rows are cached before `/predict`.
    """
    # Weather
    weather = supabase.table("weather_records").select("*").eq(
        "date", target_date
    ).execute()

    # Calendar
    calendar = supabase.table("calendar_events").select("*").eq(
        "date", target_date
    ).execute()

    return {
        "weather": weather.data[0] if weather.data else None,
        "calendar": calendar.data,
    }

async def store_predictions(target_date: str, predictions: list):
    """Store predictions in daily_predictions table (upsert)."""
    rows = [{
        "target_date": target_date,
        "bread_category_id": p["bread_category_id"],
        "predicted_demand": p["predicted_demand"],
        "confidence": p["confidence"],
        "model_version_id": p.get("model_version_id"),
    } for p in predictions]
    if rows:
        supabase.table("daily_predictions").upsert(
            rows, on_conflict="target_date,bread_category_id"
        ).execute()

async def fetch_recent_sales(category_id: str, target_date: str, days: int = 30) -> pd.DataFrame:
    """Fetch recent daily_results for historical features (rolling averages).

    Returns `sold` (actual sales — the training target) for building
    prediction-time historical features. This mirrors the training target
    so training and prediction feature distributions stay aligned.
    `lost_sales` is also fetched for reference but not used for ML training.
    Historical reruns must only see rows before the target date, so the query
    filters with result_date < target_date to prevent target leakage.
    """
    result = supabase.table("daily_results").select(
        "result_date, sold, lost_sales"
    ).eq("bread_category_id", category_id).lt(
        "result_date", target_date
    ).order(
        "result_date", desc=True
    ).limit(days).execute()

    df = pd.DataFrame(result.data)
    if not df.empty:
        df = df.sort_values("result_date")
        df["result_date"] = pd.to_datetime(df["result_date"])
        df["lost_sales"] = df["lost_sales"].fillna(0)  # NULL-safe; kept for reference only
    return df
```

### 6.3 `src/repositories/breadCategoryRepo.py`
```python
async def get_all() -> list:
    """Fetch all active bread categories, ordered by display_order."""
    result = supabase.table("bread_categories").select("*").eq(
        "is_active", True
    ).order("display_order").execute()
    return result.data
```

### 6.4 `src/repositories/modelVersionRepo.py`
```python
async def get_active_all() -> list:
    """Get all active category model versions."""
    result = supabase.table("ml_model_versions").select("*").eq(
        "is_active", True
    ).order("version", desc=True).execute()
    return result.data

async def get_active_by_category(category_id: str) -> dict | None:
    """Get the active model row for one category."""
    result = supabase.table("ml_model_versions").select("*").eq(
        "bread_category_id", category_id
    ).eq("is_active", True).order("version", desc=True).limit(1).execute()
    return result.data[0] if result.data else None

async def get_next_version() -> int:
    """Get next version number."""
    result = supabase.table("ml_model_versions").select("version").order(
        "version", desc=True
    ).limit(1).execute()
    return (result.data[0]["version"] + 1) if result.data else 1

async def insert(category_id: str, version: int, model_type: str, file_path: str, mape: float, r_squared: float, is_active: bool) -> dict:
    """Insert one category-specific model version row."""
    result = supabase.table("ml_model_versions").insert({
        "bread_category_id": category_id, "version": version,
        "model_type": model_type, "file_path": file_path,
        "mape": mape, "r_squared": r_squared, "is_active": is_active,
    }).execute()
    return result.data[0]

async def deactivate_category_except(category_id: str, version: int):
    """Set is_active=false for older versions of one category."""
    supabase.table("ml_model_versions").update(
        {"is_active": False}
    ).eq("bread_category_id", category_id).neq("version", version).execute()

async def find_by_version(version: int) -> list:
    """Return all category model rows for a version."""
    result = supabase.table("ml_model_versions").select("*").eq(
        "version", version
    ).order("bread_category_id").execute()
    return result.data
```

### 6.5 `src/repositories/featureImportanceRepo.py`
```python
async def insert_many(model_version_id: str, features: list[tuple[str, float, int]]):
    """Insert feature importance rows. features = [(name, score, rank), ...]"""
    rows = [{
        "model_version_id": model_version_id,
        "feature_name": name,
        "importance_score": score,
        "rank": rank,
    } for name, score, rank in features]
    if rows:
        supabase.table("feature_importance").insert(rows).execute()

async def find_by_version(model_version_id: str) -> list:
    result = supabase.table("feature_importance").select("*").eq(
        "model_version_id", model_version_id
    ).order("rank").execute()
    return result.data
```

---

## 7. Historical Feature-Engineering Sketch (must be adapted to `TrainingObservation.unitsSold`)

### 7.1 For Training — `build_features(df)`

```python
import pandas as pd
import numpy as np

FEATURE_COLS = [
    # A. Historical (5)
    "rolling_avg_30d", "rolling_avg_7d", "same_weekday_avg",
    "trend_7d", "yesterday_demand",
    # B. Temporal (4)
    "day_of_week", "month", "monsoon_season", "week_of_year",
    # C. External (5)
    "weather_sunny", "weather_rainy", "temp_high_c",
    "is_holiday", "holiday_multiplier",
]

def map_monsoon_season(month: int) -> int:
    if month in [11, 12, 1, 2, 3]: return 0  # northeast
    if month in [4, 10]:            return 1  # inter
    return 2                                    # southwest (5-9)

def calculate_slope(series: pd.Series) -> float:
    if len(series) < 2: return 0.0
    x = np.arange(len(series))
    return float(np.polyfit(x, series, 1)[0])

def build_features(df: pd.DataFrame) -> tuple:
    """Transform raw data into (X, y) for training.

    Training target is `sold` (actual sales — matches what a real bakery POS records).
    The simulation (Module 4) also tracks `demand` (uncapped customer attempts) and
    `lost_sales` (customers turned away) for stock-out reporting and dashboard display,
    but the ML model trains on `sold` for realism.

    Note: on stock-out days, `sold` is capped by production (e.g. demand 120, produced
    100, sold 100, lost 20), which can cause mild underprediction on similar future day
    patterns — this is an accepted tradeoff for realism. A possible future enhancement
    (censored demand recovery via `estimated_demand = sold + lost_sales`) is enabled by
    the simulation architecture but not used by default.

    Historical features are shifted so each row only sees data available
    before that date. This prevents target leakage.

    Returns: (X: DataFrame[14 cols], y: Series[sold])
    """
    df = df.sort_values("date").copy()

    # A. Historical features — shifted so today's sold is never used
    # to predict today's sold.
    sold_history = df["sold"].shift(1)
    df["rolling_avg_30d"] = sold_history.rolling(30, min_periods=1).mean()
    df["rolling_avg_7d"] = sold_history.rolling(7, min_periods=1).mean()
    df["same_weekday_avg"] = df.groupby("day_of_week")["sold"].transform(
        lambda x: x.shift(1).rolling(4, min_periods=1).mean()
    )
    df["same_weekday_avg"] = df["same_weekday_avg"].fillna(df["rolling_avg_7d"])
    df["trend_7d"] = sold_history.rolling(7, min_periods=2).apply(
        calculate_slope, raw=False
    ).fillna(0.0)
    df["yesterday_demand"] = sold_history

    # B. Temporal features
    df["monsoon_season"] = df["month"].apply(map_monsoon_season)

    # C. External features (one-hot weather)
    df["weather_sunny"] = (df["condition"] == "sunny").astype(int)
    df["weather_rainy"] = (df["condition"] == "rainy").astype(int)

    # Drop first row(s) without prior history.
    df = df.dropna(subset=["rolling_avg_30d", "rolling_avg_7d", "yesterday_demand"])

    # Training target = sold (actual sales — matches real bakery POS data)
    y = df["sold"]
    X = df[FEATURE_COLS]
    return X, y
```

### 7.2 For Prediction — `build_prediction_features(target_date, context, recent_sales)`

```python
def build_prediction_features(
    target_date: str,
    context: dict,
    recent_sales: pd.DataFrame,
) -> pd.DataFrame:
    """Build a single-row feature vector for prediction.
    Uses recent sales history + weather/calendar context for target date.

    Historical features (rolling_avg, same_weekday_avg, trend,
    yesterday_demand) are derived from `sold` (actual sales). This mirrors
    `build_features` (training) so that training-time and prediction-time
    feature distributions stay aligned.
    """
    date = pd.to_datetime(target_date)
    day_of_week = date.dayofweek + 1
    month = date.month
    week_of_year = int(date.isocalendar().week)

    weather = context.get("weather", {}) or {}
    calendar_events = context.get("calendar", [])
    condition = weather.get("condition", "cloudy")
    is_holiday = len(calendar_events) > 0
    holiday_multiplier = (
        calendar_events[0]["demand_multiplier"]
        if calendar_events else 1.0
    )

    # Historical from recent_sales — use sold (actual sales)
    if not recent_sales.empty and "sold" in recent_sales.columns:
        sold_series = recent_sales["sold"]
    else:
        sold_series = pd.Series([50])  # cold-start neutral default

    rolling_30 = sold_series.rolling(30, min_periods=1).mean().iloc[-1]
    rolling_7 = sold_series.rolling(7, min_periods=1).mean().iloc[-1]
    yesterday = sold_series.iloc[-1] if not sold_series.empty else 50

    same_week_mask = pd.to_datetime(recent_sales["result_date"]).dt.dayofweek == date.dayofweek()
    same_weekday_avg = (
        recent_sales[same_week_mask]["sold"].tail(4).mean()
        if same_week_mask.any()
        else rolling_7
    )
    trend_7d = calculate_slope(sold_series.tail(7)) if len(sold_series) >= 2 else 0.0

    row = pd.DataFrame([{
        "rolling_avg_30d": rolling_30,
        "rolling_avg_7d": rolling_7,
        "same_weekday_avg": same_weekday_avg if not np.isnan(same_weekday_avg) else rolling_7,
        "trend_7d": trend_7d,
        "yesterday_demand": yesterday,
        "day_of_week": day_of_week,
        "month": month,
        "monsoon_season": map_monsoon_season(month),
        "week_of_year": week_of_year,
        "weather_sunny": int(condition == "sunny"),
        "weather_rainy": int(condition == "rainy"),
        "temp_high_c": weather.get("temp_high_c", 28),
        "is_holiday": int(is_holiday),
        "holiday_multiplier": holiday_multiplier,
    }])

    return row[FEATURE_COLS]
```

---

## 8. Historical Service Sketches (superseded by the canonical classes in Section 2.1)

> Services contain business logic. They call repos for DB access. No direct Supabase calls. See `../ARCHITECTURE.md` §4.3.

### 8.1 `src/services/trainService.py` — Training Pipeline

```python
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from ..config.env import settings
from ..repositories import trainingDataRepo, breadCategoryRepo, modelVersionRepo, featureImportanceRepo
from ..features.feature_engineering import build_features
from ..services.evaluationService import evaluate
from ..services.dataQualityService import check_training_quality
from ..modelPersistence.persistence import save_model

class CategoryPredictor:
    """Wraps RF + LR for a single bread category."""
    def __init__(self, category_name: str):
        self.category_name = category_name
        self.rf: RandomForestRegressor | None = None
        self.lr: LinearRegression | None = None

    def train(self, X, y, n_estimators: int = 100, random_state: int = 42):
        self.rf = RandomForestRegressor(
            n_estimators=n_estimators, random_state=random_state
        )
        self.lr = LinearRegression()
        self.rf.fit(X, y)
        self.lr.fit(X, y)

    def predict(self, X) -> tuple:
        """Returns (predicted_demand, confidence/stability score) using RF."""
        if self.rf is None:
            raise ValueError("Model not trained")
        demand = float(self.rf.predict(X)[0])
        confidence = self._calc_confidence(X)
        return demand, confidence

    def predict_baseline(self, X) -> float:
        """LR prediction for comparison."""
        if self.lr is None:
            raise ValueError("Model not trained")
        return float(self.lr.predict(X)[0])

    def _calc_confidence(self, X) -> float:
        """Tree variance → confidence/stability score."""
        from .confidenceService import calculate_confidence
        return calculate_confidence(self.rf, X)

    def feature_importance(self, feature_names) -> list:
        """Returns [(name, score), ...] sorted desc."""
        scores = self.rf.feature_importances_
        return sorted(zip(feature_names, scores), key=lambda x: x[1], reverse=True)
```

### 8.2 `src/services/trainService.py` — Training Pipeline (continued)

```python
from ..config.env import settings
from ..repositories import trainingDataRepo, breadCategoryRepo
from ..features.feature_engineering import build_features
from ..services.evaluationService import evaluate
from ..modelPersistence.persistence import save_model

async def train_category_model(category: dict) -> dict:
    """Train RF + LR for one category.
    Returns: { status, predictor, metrics, feature_importance } or { status: 'cold_start' }
    """
    df = await trainingDataRepo.fetch_training_data(category["id"])  # Repo call
    quality = check_training_quality(df)
    if len(df) < settings.MIN_TRAINING_DAYS:
        return {"status": "cold_start", "category": category["name"], "quality": quality}

    X, y = build_features(df)

    # Time-based split (last 20% as test)
    split_idx = int(len(X) * (1 - settings.TEST_SPLIT_RATIO))
    X_train, X_test = X.iloc[:split_idx], X.iloc[split_idx:]
    y_train, y_test = y.iloc[:split_idx], y.iloc[split_idx:]

    predictor = CategoryPredictor(category["name"])
    predictor.train(X_train, y_train, settings.RF_N_ESTIMATORS, settings.RF_RANDOM_STATE)

    rf_metrics = evaluate(predictor.rf, X_test, y_test)
    lr_metrics = evaluate(predictor.lr, X_test, y_test)
    importance = predictor.feature_importance(list(X.columns))

    return {
        "status": "trained",
        "category_id": category["id"],
        "category": category["name"],
        "predictor": predictor,
        "rf_metrics": rf_metrics,
        "lr_metrics": lr_metrics,
        "feature_importance": importance,
        "quality": quality,
    }

async def train_all_categories() -> dict:
    """Train models for all 4 bread categories.
    Returns: { 'Croissants': {...}, 'Sweet Bread': {...}, ... }
    """
    categories = await get_bread_categories()
    results = {}
    for category in categories:
        result = await train_category_model(category)
        results[category["name"]] = result
    return results
```

### 8.3 `src/services/evaluationService.py` — Pure calculation (no DB)

```python
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import numpy as np

def evaluate(model, X_test, y_test) -> dict:
    """Calculate MAE, RMSE, MAPE, R²."""
    preds = model.predict(X_test)
    mae = mean_absolute_error(y_test, preds)
    rmse = float(np.sqrt(mean_squared_error(y_test, preds)))
    # MAPE: avoid division by zero
    mask = y_test != 0
    mape = float(np.mean(np.abs((y_test[mask] - preds[mask]) / y_test[mask])) * 100) if mask.any() else 0.0
    r2 = r2_score(y_test, preds)
    return {
        "mae": float(mae),
        "rmse": rmse,
        "mape": mape,
        "r_squared": float(r2),
    }
```

### 8.4 `src/services/dataQualityService.py` — Pure checks (no DB)

```python
def check_training_quality(df) -> dict:
    """Return simple data quality signals for manager/model status."""
    if df.empty:
        return {
            "row_count": 0,
            "missing_weather_days": 0,
            "stock_out_days": 0,
            "zero_sales_days": 0,
            "warnings": ["No training rows found"],
        }

    missing_weather = int(df["condition"].isna().sum()) if "condition" in df else 0
    stock_out_days = (
        int((df["lost_sales"].fillna(0) > 0).sum())
        if "lost_sales" in df else 0
    )
    zero_sales_days = int((df["sold"] == 0).sum()) if "sold" in df else 0

    warnings = []
    if len(df) < 90:
        warnings.append("Less than 90 days of history; evaluation may be weak")
    if missing_weather:
        warnings.append(f"{missing_weather} rows missing weather context")
    if zero_sales_days:
        warnings.append(f"{zero_sales_days} zero-sales days need review")
    if stock_out_days:
        warnings.append(f"{stock_out_days} stock-out days may bias sold-based training")

    return {
        "row_count": int(len(df)),
        "missing_weather_days": missing_weather,
        "stock_out_days": stock_out_days,
        "zero_sales_days": zero_sales_days,
        "warnings": warnings,
    }
```

### 8.5 `src/modelPersistence/persistence.py` — File I/O (not DB)

```python
import joblib
from pathlib import Path
from ..config.env import settings

def save_model(model, category_name: str, version: int, model_type: str) -> str:
    """Save model to disk as joblib file.
    Path: models/{category}_{type}_v{version}.joblib
    """
    Path(settings.MODEL_DIR).mkdir(parents=True, exist_ok=True)
    slug = category_name.lower().replace(" ", "_")
    filename = f"{slug}_{model_type}_v{version}.joblib"
    path = Path(settings.MODEL_DIR) / filename
    joblib.dump(model, path)
    return str(path)

def load_model(category_name: str, version: int, model_type: str = "rf"):
    """Load model from disk."""
    slug = category_name.lower().replace(" ", "_")
    filename = f"{slug}_{model_type}_v{version}.joblib"
    path = Path(settings.MODEL_DIR) / filename
    if not path.exists():
        raise FileNotFoundError(f"Model file not found: {path}")
    return joblib.load(path)
```

---

## 9. Historical Prediction Sketches (confidence formula and DB calls are not approved)

### 9.1 `src/services/confidenceService.py` — Pure calculation (no DB)

```python
import numpy as np

def calculate_confidence(rf_model, X) -> float:
    """Calculate a confidence/stability score from RF tree variance.
    Low variance across trees = high model agreement.

    Mapping:
    - CV=0.05 → stability ≈ 93%
    - CV=0.15 → stability ≈ 83%
    - CV=0.25 → stability ≈ 73%
    - Clamped to [50, 98]

    This is not a probability that demand will equal the exact predicted value.
    """
    all_tree_preds = np.array([tree.predict(X)[0] for tree in rf_model.estimators_])
    pred_mean = np.mean(all_tree_preds)
    pred_std = np.std(all_tree_preds)

    if pred_mean == 0:
        return 50.0

    cv = pred_std / pred_mean  # coefficient of variation
    stability = 98 - (cv * 100)
    return float(max(50.0, min(98.0, stability)))
```

### 9.2 `src/services/coldStartService.py` — Heuristic fallback (calls repos)

```python
from datetime import datetime
from ..features.constants import load_constants, get_season_multiplier

async def cold_start_predict(target_date: str, context: dict) -> dict:
    """Heuristic prediction using constants.json multipliers.
    Used when <30 days of historical data exists.
    """
    constants = load_constants()
    date = datetime.fromisoformat(target_date)
    day_name = date.strftime("%A")
    month = date.month

    weather = context.get("weather", {}) or {}
    calendar_events = context.get("calendar", [])
    condition = weather.get("condition", "cloudy")
    holiday_mult = (
        calendar_events[0]["demand_multiplier"]
        if calendar_events else 1.0
    )

    dow_mult = constants["dow_multipliers"][day_name]
    weather_mult = constants["weather_multipliers"].get(condition, 1.0)
    season_mult = get_season_multiplier(constants, month)

    predictions = []
    for category in constants["bread_categories"]:
        base = constants["base_daily_demand"][category["name"]]
        demand = base * dow_mult * weather_mult * season_mult * holiday_mult
        predictions.append({
            "bread_category_id": None,  # filled by caller from DB
            "category_name": category["name"],
            "predicted_demand": int(round(demand)),
            "confidence": 65.0,
        })

    return {
        "date": target_date,
        "predictions": predictions,
        "model_version": None,
        "mode": "cold_start",
    }
```

### 9.3 `src/services/predictService.py` — Full prediction flow (calls repos)

```python
from ..repositories import predictionRepo, breadCategoryRepo, modelVersionRepo
from ..features.feature_engineering import build_prediction_features
from ..modelPersistence.persistence import load_model
from .coldStartService import cold_start_predict
from .confidenceService import calculate_confidence

async def predict(target_date: str) -> dict:
    """Full prediction flow for all categories.
    Returns: { date, predictions: [{ category, demand, confidence }], model_version }
    """
    context = await predictionRepo.fetch_prediction_context(target_date)
    categories = await breadCategoryRepo.get_all()

    # Whole-system cold start: no active category model rows.
    active_rows = await modelVersionRepo.get_active_all()
    if not active_rows:
        result = await cold_start_predict(target_date, context)
        cat_map = {c["name"]: c["id"] for c in categories}
        for p in result["predictions"]:
            p["bread_category_id"] = cat_map.get(p["category_name"])
            p["model_version_id"] = None
        await predictionRepo.store_predictions(target_date, result["predictions"])
        return result

    active_by_category = {row["bread_category_id"]: row for row in active_rows}
    predictions = []
    used_fallback = False
    for category in categories:
        active_model = active_by_category.get(category["id"])
        if active_model is None:
            used_fallback = True
            fallback = await cold_start_predict(target_date, context)
            fallback_row = next(p for p in fallback["predictions"] if p["category_name"] == category["name"])
            fallback_row["bread_category_id"] = category["id"]
            fallback_row["model_version_id"] = None
            predictions.append(fallback_row)
            continue

        recent_sales = await predictionRepo.fetch_recent_sales(category["id"], target_date, 30)

        try:
            rf = load_model(category["name"], active_model["version"], "rf")
        except FileNotFoundError:
            used_fallback = True
            fallback = await cold_start_predict(target_date, context)
            fallback_row = next(p for p in fallback["predictions"] if p["category_name"] == category["name"])
            fallback_row["bread_category_id"] = category["id"]
            fallback_row["model_version_id"] = None
            predictions.append(fallback_row)
            continue

        X = build_prediction_features(target_date, context, recent_sales)
        demand = float(rf.predict(X)[0])
        confidence = calculate_confidence(rf, X)

        predictions.append({
            "bread_category_id": category["id"],
            "category_name": category["name"],
            "predicted_demand": int(round(demand)),
            "confidence": float(round(confidence, 1)),
            "model_version_id": active_model["id"],
        })

    await predictionRepo.store_predictions(target_date, predictions)
    return {
        "date": target_date,
        "predictions": predictions,
        "model_version": max(row["version"] for row in active_rows),
        "mode": "mixed_fallback" if used_fallback else "rf",
    }
```

---

## 10. `[RETIRED — DO NOT IMPLEMENT]` Controller/Router Sketches

### 10.1 `src/controllers/health_controller.py`
```python
from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
async def health():
    return {"status": "ok", "service": "ml_server"}
```

### 10.2 `src/controllers/predict_controller.py`
```python
from fastapi import APIRouter
from pydantic import BaseModel
from ..prediction.predict_service import predict

router = APIRouter()

class PredictRequest(BaseModel):
    target_date: str  # ISO date: "2026-06-26"

@router.post("/predict")
async def predict_endpoint(req: PredictRequest):
    result = await predict(req.target_date)
    return result
```

### 10.3 `src/controllers/retrain_controller.py`
```python
from fastapi import APIRouter
from ..services.trainService import train_all_categories
from ..modelPersistence.persistence import save_model
from ..repositories import modelVersionRepo, featureImportanceRepo

router = APIRouter()

@router.post("/retrain")
async def retrain():
    """Retrain all models on latest historical data.
    Called manually by an admin/manager when enough new historical data exists.
    """
    results = await train_all_categories()  # Service call

    # Get next version number (Repo call)
    next_version = await modelVersionRepo.get_next_version()

    trained = []
    cold_start = []
    for name, result in results.items():
        if result["status"] == "cold_start":
            cold_start.append(name)
            continue

        # Save models to disk (file I/O)
        rf_path = save_model(result["predictor"].rf, name, next_version, "rf")
        lr_path = save_model(result["predictor"].lr, name, next_version, "lr")

        # Insert ml_model_versions row (Repo call)
        version_row = await modelVersionRepo.insert(
            category_id=result["category_id"],
            version=next_version,
            model_type="random_forest",
            file_path=rf_path,
            mape=result["rf_metrics"]["mape"],
            r_squared=result["rf_metrics"]["r_squared"],
            is_active=True,
        )

        # Insert feature_importance rows (Repo call)
        features = [(feat, float(score), rank) for rank, (feat, score) in enumerate(result["feature_importance"], 1)]
        await featureImportanceRepo.insert_many(version_row["id"], features)

        await modelVersionRepo.deactivate_category_except(result["category_id"], next_version)
        trained.append(name)

    return {
        "status": "complete",
        "version": next_version,
        "models_trained": trained,
        "cold_start_categories": cold_start,
        "metrics": {n: r.get("rf_metrics") for n, r in results.items() if r.get("rf_metrics")},
    }
```

### 10.4 `src/controllers/model_controller.py`
```python
from fastapi import APIRouter
from ..repositories import modelVersionRepo, featureImportanceRepo

router = APIRouter()

@router.get("/model/active")
async def get_active_model():
    models = await modelVersionRepo.get_active_all()  # Repo call
    if not models:
        return {"error": "No active models", "models": []}
    return {"models": models}

@router.get("/model/{version}/importance")
async def get_feature_importance(version: int):
    # Get all category model rows for the version (Repo call)
    model_rows = await modelVersionRepo.find_by_version(version)
    if not model_rows:
        return {"error": "Version not found"}
    result = []
    for row in model_rows:
        features = await featureImportanceRepo.find_by_version(row["id"])
        result.append({
            "bread_category_id": row["bread_category_id"],
            "model_version_id": row["id"],
            "features": features,
        })
    return {"version": version, "categories": result}
```

### 10.5 `src/controllers/evaluate_controller.py`
```python
from fastapi import APIRouter
from ..services.trainService import train_all_categories

router = APIRouter()

@router.get("/evaluate")
async def evaluate_models():
    """Run evaluation on current data (without saving models).
    Returns metrics for all categories.
    """
    results = await train_all_categories()  # Service call
    return {
        name: {
            "status": r["status"],
            "rf_metrics": r.get("rf_metrics"),
            "lr_metrics": r.get("lr_metrics"),
        }
        for name, r in results.items()
    }
```

---

## 11. App Setup

### 11.1 `src/app.py`
```python
from fastapi import FastAPI
from .controllers.health_controller import router as health_router
from .controllers.predict_controller import router as predict_router
from .controllers.retrain_controller import router as retrain_router
from .controllers.model_controller import router as model_router
from .controllers.evaluate_controller import router as evaluate_router

app = FastAPI(title="Bakery ML Server", version="0.1.0")

app.include_router(health_router)
app.include_router(predict_router)
app.include_router(retrain_router)
app.include_router(model_router)
app.include_router(evaluate_router)
```

### 11.2 `src/server.py`
```python
import uvicorn

if __name__ == "__main__":
    uvicorn.run("src.app:app", host="0.0.0.0", port=8000, reload=True)
```

---

## 12. Historical Request/Response Flow (superseded by Section 2.1)

```
Node.js (orchestrator)
  ├─ Fetch/cache weather + calendar context via Module 1
  ↓ POST /predict { target_date: "2026-06-26" }
FastAPI ML Server
  ├─ Fetch cached weather + calendar context from Supabase
  ├─ Check active category model rows in Supabase
  │
  ├─ IF no active category models (cold start):
  │   ├─ cold_start_predict() using constants.json multipliers
  │   │   └─ base × dow × weather × season × holiday
  │   ├─ Confidence/stability: 65% (fixed)
  │   └─ Store predictions in daily_predictions
  │
  └─ IF active category models exist:
      ├─ For each of 4 categories:
      │   ├─ Load RF model from disk (joblib)
      │   ├─ Fetch recent 30 days sales
      │   ├─ Build 14-feature vector
      │   ├─ rf.predict(X) → demand
      │   ├─ Tree variance → confidence/stability
      │   └─ If model row/file missing → fallback for that category
      ├─ Store predictions in daily_predictions
      └─ Return { date, predictions, model_version, mode: "rf" | "mixed_fallback" }
  ↓
Node.js receives response → forwards to Flutter
```

---

## 13. Historical Retrain Flow (superseded by candidate/evaluation/activation lifecycle)

```
Manager/Admin action from dashboard or API client
  ↓ POST /retrain
FastAPI ML Server
  ├─ For each of 4 categories:
  │   ├─ Fetch training data (daily_results + weather + calendar, merged by date)
  │   │   → SELECT includes sold, lost_sales
  │   ├─ IF <30 days → mark cold_start, skip
   │   └─ IF ≥30 days:
   │       ├─ Build 14-feature vectors
   │       │   → historical features derived from prior sold values only
   │       │   → training target y = sold (actual sales — matches real bakery POS)
   │       ├─ Time-split (80% train, 20% test)
   │       ├─ Train RF + LR on (X, sold)
   │       ├─ Evaluate: MAE, RMSE, MAPE, R² (against sold)
   │       ├─ Extract feature_importance
   │       └─ Save models to disk (joblib)
   │
   ├─ Insert one ml_model_versions row per trained category
   ├─ Insert feature_importance rows
   ├─ Deactivate previous model versions
   └─ Return summary { version, trained, cold_start, metrics }
   ↓
Node.js logs result and updates dashboard metrics
```

> **Training target:** The ML model trains on `sold` (actual sales) — the same data a real bakery POS would record. The simulation (Module 4) also tracks `demand` (uncapped customer attempts) and `lost_sales` (customers turned away) in the `daily_results` table for stock-out reporting and dashboard display, but the ML model trains on `sold` for realism.
>
> **Accepted tradeoff:** On stock-out days, `sold` is capped by production (e.g. demand 120, produced 100, sold 100, lost 20), which can cause mild underprediction on similar future day patterns. This is an accepted tradeoff for realism — matching what a real bakery would observe.
>
> **Possible future enhancement:** The simulation architecture enables "censored demand recovery" by training on `estimated_demand = sold + lost_sales` instead. This would teach the model the true underlying customer demand (what people *wanted* to buy, not what inventory allowed). This is not used by default but could be enabled as a configuration option. This concept (censored data in demand forecasting) is worth mentioning in the viva as a design awareness point.

---

## 14. Verification Plan

| Step | Command | Expected Result |
|---|---|---|
| 1 | `cd ml_server && pip install -r requirements.txt` | Dependencies installed |
| 2 | `python -m src.server` | Server starts on port 8000 |
| 3 | `GET /health` | 200 `{ status: "ok", service: "ml_server" }` |
| 4 | `POST /predict { target_date: "2026-06-26" }` (no model yet) | Cold-start heuristic, confidence 65%, mode: "cold_start" |
| 5 | `POST /retrain` (after Module 0 seed: 90 days data) | Trains 4 RF + 4 LR, saves joblib, returns metrics |
| 6 | `POST /predict { target_date: "2026-06-27" }` (after retrain) | RF prediction, confidence/stability 70-98%, mode: "rf" |
| 7 | `GET /model/active` | Returns 4 active category model rows with MAPE + R² |
| 8 | `GET /model/1/importance` | Returns ranked features per category (day_of_week, weather, etc.) |
| 9 | `GET /evaluate` | Returns MAE, RMSE, MAPE, R² per category |
| 10 | Check Supabase `daily_predictions` | Rows with predicted_demand + confidence |
| 11 | Check Supabase `ml_model_versions` | 4 version rows with `bread_category_id`, `is_active=true`, MAPE, R² |
| 12 | Check Supabase `feature_importance` | Feature rows with scores + ranks |
| 13 | Check `ml_server/models/` | 8 joblib files (4 RF + 4 LR) |
| 14 | Inspect feature engineering output | Rolling features use only previous rows; current-day `sold` is not used in its own features |
| 15 | Historical leakage check | Re-run prediction for a past date and confirm `fetch_recent_sales` filters `daily_results.result_date < target_date` |

---

## 15. Implementation Order

1. Create `requirements.txt` + `.env.example`
2. Create `src/config/` (env.py, supabase.py)
3. Create `src/repositories/` (trainingDataRepo, predictionRepo, modelVersionRepo, featureImportanceRepo, breadCategoryRepo)
4. Create `src/features/constants.py` (load constants.json)
5. Create `src/features/feature_engineering.py` (build_features + build_prediction_features)
6. Create `src/services/` (trainService, predictService, confidenceService, coldStartService, evaluationService)
7. Create `src/modelPersistence/persistence.py` (joblib save/load)
8. Create `src/controllers/` (all 5 controller files)
9. Create `src/app.py` + `src/server.py`
10. Create `src/utils/logger.py`
11. Create `models/` directory (for joblib files)
12. Install deps: `pip install -r requirements.txt`
13. Verify: run server + test endpoints

---

## 16. Open Items for Implementation

| # | Item | Notes |
|---|---|---|
| 1 | Context availability | Ensure Module 1 fetches/caches weather + calendar before `/predict`; fallback to neutral context if rows are missing |
| 2 | Feature consistency | Ensure `build_features` (training) and `build_prediction_features` (inference) produce identical 14-column order |
| 3 | Data quality checks | Report missing weather dates, low row count, stock-out count, and zero-sales days before training |
| 4 | Model versioning race condition | If `/retrain` is called twice simultaneously, version numbers could collide — add a simple lock or unique constraint handling |
| 5 | Weather one-hot completeness | Only `weather_sunny` and `weather_rainy` are one-hot; cloudy/thunderstorm/haze are baseline. Consider if this is sufficient |
| 6 | Historical prediction reruns | `fetch_recent_sales(category_id, target_date, days)` must always filter with `result_date < target_date`; never use latest rows without a target-date boundary |

---

**Plan Status:** Complete. Ready for implementation on your signal.
