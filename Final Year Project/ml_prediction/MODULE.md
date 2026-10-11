# Module 2: ML Prediction — Proposed Module Plan

Reconciled on 2026-10-11 against the latest `RSW_SooKinMin_Project1 (1).docx`, Sections 1.4.2, 3.5–3.6, 4.2, 4.5, 4.8 and 4.9.2. The repository contains a Flutter starter and planning documents; these components and checks are proposed, not implemented or tested. The report takes precedence over earlier July planning assertions. See the [detailed contract](README.md), [architecture](../ARCHITECTURE.md), [database design](../../database_canonical_design.md) and [traceability matrix](../../planning_documents_change_report.md).

## 1. Scope and functional-module mapping

Technical Module 2 primarily delivers **Demand Prediction** and supports **Reporting and Dashboard**, **Alerts and Notifications**, and **System Administration**. Build modules 0–6 coexist with the eight functional modules in Section 1.4.2.

Predict next-day units sold for configured active categories in one Android bakery application. Four bread categories and five ingredients are seed examples. Design and verification cover up to 20 active categories and 365 daily records per category. Prediction generation is a Bakery Manager action; training, evaluation, activation and restoration are distinct System Administrator actions. No scheduled prediction or retraining is planned.

## 2. Dependencies and ownership

Module 0 defines provenance, mode-dependent confidence and retained model metadata. Module 1 verifies JWT and the ACTIVE stored profile, enforces its single role, reads PostgreSQL through Repos, builds validated DTOs and calls `FastApiMlClient`. Flutter business requests go through TypeScript Controller classes and Services. Flutter's direct Supabase Authentication, recipient-scoped foreground Realtime and FCM notification paths are platform exceptions; they give no access to ML administration or ordinary table CRUD.

FastAPI receives Node data through thin route modules. Python Services calculate features, train/evaluate models and predict. `ModelArtifactStore` handles versioned files. FastAPI has no Supabase client, database Repo, database credentials or activation capability.

## 3. Planned components

| Component | Responsibility |
|---|---|
| `PredictionController` / `PredictionOrchestrationService` (Node) | Manager-only prediction request, active categories, history/context DTO, atomic returned-prediction persistence |
| `ModelManagementController` / `ModelManagementService` (Node) | Administrator-only candidate training, evaluation, explicit activation/restoration; preserve active version on failure |
| `DailySalesRecordRepo`, `DailyPredictionRepo`, `MlModelVersionRepo`, `ModelEvaluationRepo`, `FeatureImportanceRepo` | Node-owned observations, predictions and model metadata |
| `FastApiMlClient` | Validated request/response boundary to thin `/predict`, `/train`, `/evaluate` routes |
| `HistorySelectionService` (Node) | Select one validated origin-prioritized observation per category/day before threshold counting and DTO construction |
| `FeaturePreparationService` | Chronological features from selected `unitsSold` observations without future leakage |
| `PredictionService` | Per-category MODEL/COLD_START selection and Python calculation orchestration |
| `ConfidenceService` | Dedicated Random Forest tree-agreement formula and threshold evaluation |
| `ColdStartService` | Available-observation mean or configured base, with configured contextual factors |
| `ModelTrainingService`, `ModelEvaluationService` | RF candidate and LR comparison on identical datasets; all four metrics |
| `RandomForestModel`, `LinearRegressionModel`, `ModelArtifactStore` | Estimator wrapper and retained artifact storage |
| `PredictionView`, `ModelManagementView` | Correct role actions, nullable confidence, provenance and lifecycle confirmation |

Route modules register handlers; they are not Controller UML classes. See the [logical design](../../logical_view_canonical_design.md).

## 4. Prediction and data rules

Select one **validated** observation per category/day in `ACTUAL_TRANSACTION` → `IMPORTED_HISTORICAL` → `SIMULATION_GENERATED` priority order. Count distinct selected days for the 30-day threshold. Training and comparable prediction-performance evaluation use `DailySalesRecord.unitsSold`; `estimatedDemand = unitsSold + lostSales` remains analytical.

Use Random Forest only with at least 30 distinct validated daily observations and a valid active model. With tree-prediction mean `mu` and standard deviation `sigma`, Section 4.9.2 defines:

```text
predicted_units_sold = max(0, round(mu))
confidence = 100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))
```

MODEL requires numerical confidence in [0,100] and a model-version reference. Low Confidence is below the configurable threshold, initially 75%; equality is not below threshold. Confidence measures tree agreement, not forecast-correctness probability or guaranteed improvement.

For COLD_START, `Bc` is the mean of available selected valid `unitsSold` observations. Use the configured category base only if no valid observation exists. Apply weekday `Dt`, monsoon `Mt`, weather `Wt` and holiday `Ht` factors:

```text
cold_start_prediction = max(0, round(Bc * Dt * Mt * Wt * Ht))
prediction_mode = COLD_START
model_version_id = null
confidence = null
label = Low-confidence heuristic estimate
```

Cold-start confidence is never a configurable numeric score. UI and dashboard omit a percentage for this mode (NFR-ACC-08).

## 5. Candidate lifecycle and evaluation

Training produces retained inactive candidates. Parameter selection uses earlier training/validation observations; the later test set is untouched by fitting and parameter selection. RF and LR share train/test observations. Evaluation stores MAE, RMSE, MAPE and R² with origin composition and unavailable-metric reasons. Zero actuals remain in MAE/RMSE and are excluded only from MAPE. Undefined metrics are unavailable, never perfect scores.

An administrator explicitly evaluates and activates a candidate. Under NFR-ACC-05, reject activation if its MAE exceeds the active model's MAE on the **same** later test dataset. Missing/noncomparable evaluation blocks replacement. Preserve the active model on every failure. Restoration is an explicit audited transaction on a retained valid version. MAPE < 10% and R² > 0.85, if explored, are aspirational research targets, not report acceptance criteria or achieved results.

## 6. Contracts, implementation order and verification

The [README](README.md) defines role-controlled endpoints, discriminated DTOs, SQL invariants, algorithms and failure checks. Implement later: contracts/provenance selection; Node DTO/persistence boundary; Python feature/cold-start/confidence services; candidates and holdout evaluation; transactional lifecycle; prediction/UI/report integration; planned checks.

Verify origin priority and duplicate-day counting; 29/30-day and missing-model boundaries; exact confidence boundaries; null COLD_START confidence across SQL/Zod/Pydantic/Dart; chronological leakage; unavailable MAPE/R²; higher-MAE rejection on a common dataset; rollback and retained artifacts; both cross-role rejections; and prediction within 15 seconds under NFR-PER-02. No testing outcomes are claimed.
