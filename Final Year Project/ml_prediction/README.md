# Module 2: ML Prediction — Detailed Proposed Design

Reconciled on 2026-10-11 from the latest `RSW_SooKinMin_Project1 (1).docx`, especially Sections 3.5–3.6, 4.2, 4.5.3–4.5.4, 4.8 and 4.9.2. Formula images in Section 4.9.2 are part of the source. That date records the design audit, not the current implementation state.

Historical implementation status on 2026-11-04: Node had validated history selection, a `FastApiMlClient`, administrator model review/lifecycle endpoints, manager `POST /api/predictions`, and role-permitted `GET /api/predictions/next` and `GET /api/predictions/:date`. The manager Service built next-day DTOs for every active category from selected history, configured factors, stored weather/calendar context and the active model; the fifth staged migration added a context snapshot and one atomic batch-persistence RPC. Explicitly configured context fallbacks were labelled. Flutter had a next-day `PredictionView` and an administrator `ModelManagementView`. FastAPI had cold-start prediction, feature preparation, candidate RF/LR fitting, retained artifacts, RF inference, holdout evaluation and artifact validation. **Current local status (2026-11-12):** Node also prepares linked saved historical context and synchronises KUL public holidays on demand. The KL holiday migration is staged and **has not been applied or verified against the live database**. Local tests do not establish live provider connectivity, achieved model accuracy, performance or user acceptance.

See [module scope](MODULE.md), [architecture](../ARCHITECTURE.md), [canonical schema](../../database_canonical_design.md), [logical design](../../logical_view_canonical_design.md) and [requirement traceability](../../planning_documents_change_report.md). The report governs; prior July design assertions have no overriding authority.

## 1. Responsibilities and permissions

Technical Module 2 maps to Demand Prediction, with reporting, notification and administrative integration. Prediction serves configured active categories for one Android bakery. Four categories/five ingredients are sample seeds, not application limits. Reference workload: up to 20 categories and 365 daily records/category.

| Operation | Authorized role | Planned boundary |
|---|---|---|
| Generate next-day predictions | BAKERY_MANAGER only | `PredictionController → PredictionOrchestrationService` |
| View permitted prediction history/dashboard | Both ACTIVE roles | Node read Service and Repos |
| Train candidate, evaluate, activate, restore | SYSTEM_ADMINISTRATOR only | `ModelManagementController → ModelManagementService` |
| View own low-confidence/failure notifications | Intended authenticated recipient | `NotificationService`, recipient Realtime policy and notification Views |

Node validates JWT signature, issuer, audience and expiry, then loads `user_profiles` and rejects missing/INACTIVE profiles before role checks. It uses the one stored role and authenticated actor, never email or client claims about actor/role. Supabase Auth, recipient-only foreground Realtime and FCM are Flutter platform exceptions; all business CRUD uses Node. No background operation initiates prediction or training.

## 2. Proposed architecture and component contracts

```mermaid
flowchart LR
  PV[PredictionView] --> PC[PredictionController]
  PC --> PO[PredictionOrchestrationService]
  PO --> NR[Node Repos]
  PO --> FC[FastApiMlClient]
  MV[ModelManagementView] --> MC[ModelManagementController]
  MC --> MM[ModelManagementService]
  MM --> NR
  MM --> FC
  NR --> DB[(PostgreSQL)]
  FC --> R[Thin FastAPI route modules]
  R --> PS[PredictionService]
  R --> MT[ModelTrainingService]
  R --> ME[ModelEvaluationService]
  PS --> FP[FeaturePreparationService]
  PS --> CS[ConfidenceService]
  PS --> CC[ColdStartService]
  PS --> AS[ModelArtifactStore]
  MT --> FP
  MT --> AS
  ME --> FP
  ME --> AS
```

The arrows express dependencies, not database access from Python. Routes are registration modules, not UML Controller classes. Repos are TypeScript classes: `DailySalesRecordRepo`, `BreadCategoryRepo`, `DailyPredictionRepo`, `MlModelVersionRepo`, `ModelEvaluationRepo`, `FeatureImportanceRepo`, `WeatherRepo` and `KlHolidayRepo`. Services use these Repos and adapters; Controllers only delegate to Services.

`FastApiMlClient` supplies validated DTOs. FastAPI has no Supabase client, credential, database Repo or activation endpoint. `ModelArtifactStore` reads/writes retained model files only; safe artifact identifiers come from the trusted Node contract, not arbitrary client paths.

## 3. Historical observations and feature preparation

The training target and comparable prediction-performance actual are `DailySalesRecord.unitsSold` (SQL `units_sold`). `lostSales` and `estimatedDemand = unitsSold + lostSales` remain operational analytics.

Node's normal `HistorySelectionService` selects only validated non-simulated rows, groups by category/business date and chooses one row per group:

1. `ACTUAL_TRANSACTION`
2. `IMPORTED_HISTORICAL`

`SIMULATION_GENERATED` is retained in storage and reporting, but excluded from normal training, primary evaluation, prediction lag history and the 30-day threshold. No simulation-only experiment path is currently exposed. The enum/DTO origin labels remain unchanged so older artifacts and metrics keep their provenance.

Origin-specific uniqueness prevents duplicates within an origin; invalid actual rows do not suppress valid imported rows. Unresolved same-origin duplicates are rejected for validation rather than silently counted twice. The model threshold counts distinct selected valid non-simulated days, not raw rows. Actual/imported rows retain their external source reference; simulation rows keep `source_daily_result_id` for reporting and legacy traceability.

Only records preceding the prediction target date may contribute historical features. Planned features include lag sales, shifted rolling averages/trends and same-weekday history; day/weekend/month/monsoon; weather; and holiday information. Fit preprocessing only on the permitted training period. Validation is chronologically after training, and the untouched final test period is later still. Missing-feature handling and configurable feature windows must be recorded with the candidate, with context defaults marked for traceability.

Node owns weather/calendar retrieval and persists prediction references through `weather_record_id`, `prediction_calendar_events` and the context snapshot. The manager endpoint reads stored context and, if next-day weather is absent, tries the server-configured OpenWeather forecast adapter before inference. A validated forecast is cached once; `weather_records` are forecast provenance, not actual historical weather. For KUL public holidays, Node checks separate successful year coverage, synchronises the published Malaysia Holiday API year when needed once per prediction batch, then resolves the target date from current stored KL events. Missing coverage uses an explicit fallback or clear error; a missing event with valid coverage is a verified ordinary date. Corrections retain old event rows, links and prediction snapshots. Legacy manual events remain for traceability and do not inform new KL predictions. The setup example uses neutral factors, while administrator changes may select other values. Cost, price, revenue and gross profit do not enter the prediction target or recommendation logic.

For legacy simulation records, the saved-context reader can still follow `daily_sales_records.source_daily_result_id -> daily_results.prediction_id -> daily_predictions.context_snapshot.factors` and validate category/date identity. Normal selected history now consists of actual/imported records, which use neutral factors and `historical_context_defaulted = 1`; no old forecast is reconstructed. The target prediction uses its own target-date context. Feature version 1 and artifact format do not change. Existing active artifacts remain loadable, but models fitted on synthetic observations or neutral factors are not evidence of real-world accuracy. Excluding simulation rows changes selected-history fingerprints, so some existing candidates may fail evaluation until deliberately retrained; checks are not bypassed. `historicalContextDefaultCount` still counts defaulted feature rows (the first observation has no prior-sales feature row).

## 4. Exact prediction algorithms

For each active category, MODEL requires **both** at least 30 distinct validated selected daily observations and a valid active Random Forest artifact. Otherwise return COLD_START with the reason. A missing/corrupt artifact is an operational warning, never a fabricated MODEL prediction.

`ConfidenceService` receives the predictions from all Random Forest trees. Let `mu` be their arithmetic mean and `sigma` their standard deviation. Section 4.9.2 specifies:

```text
predicted_units_sold = max(0, round(mu))
confidence = 100 * max(0, min(1, 1 - sigma / max(abs(mu), 1)))
is_low_confidence = confidence < configured_threshold  # initially 75
```

Calculate from the tree values before rounding the predicted units or display percentage. Nonfinite/empty tree output is a calculation failure, not zero confidence. Store the defined numerical value without imposing a display scale; determine the label from that persisted value before display rounding. A score just below 75 remains Low Confidence even if its displayed percentage rounds to 75. Confidence measures tree agreement. It is not accuracy probability and need not improve as history grows.

For COLD_START:

```text
selected = valid origin-prioritized observations for the category before target date
Bc = mean(selected.unitsSold) if selected is nonempty else configured_category_base
prediction = max(0, round(Bc * Dt * Mt * Wt * Ht))
predictionMode = COLD_START
modelVersionId = null
confidence = null
lowConfidence = true
```

`Dt`, `Mt`, `Wt`, `Ht` are configured weekday, monsoon, weather and holiday factors. A valid observed zero is included in the mean; it does not trigger the configured-base fallback. For the report's round operator, this plan chooses nearest integer with half ties away from zero across Python/Node/Dart; this is an engineering convention, not an additional report requirement. Do not rely on differing language-default tie behavior. Verify 2.5 -> 3 and 3.5 -> 4 for both prediction paths before the nonnegative clamp. `ColdStartService` owns this heuristic; it does not call `ConfidenceService`.

| Example | Expected proposed result |
|---|---|
| `mu=100, sigma=0` | 100 units, confidence 100 |
| `mu=100, sigma=25` | Confidence 75; not Low Confidence at a 75 threshold |
| `mu=100, sigma=26` | Confidence 74; Low Confidence |
| `mu=0, sigma=0` | 0 units, confidence 100 by the defined formula |
| `mu=0.2, sigma=0.8` | Confidence 20; denominator is 1 |
| `sigma >= max(abs(mu),1)` | Confidence 0 after clamping |
| Valid cold-start sales 10 and 14; base setting 99; all factors 1 | 12 units, null confidence; base setting is unused |
| No valid observations; base setting 20; factors 1.2, 1, 0.8, 1 | 19 units after rounding; null confidence |

These are formula examples, not achieved model performance.

## 5. Mode-dependent contracts across layers

Boundary DTO field names are camelCase. Node maps them explicitly to SQL snake_case: `predictedUnitsSold → predicted_units_sold`, `predictionMode → prediction_mode`, `modelVersionId → model_version_id`. Controlled values remain uppercase.

Proposed Zod/TypeScript example; it is not an implemented file:

```typescript
const PredictionCommon = z.object({
  breadCategoryId: z.string().uuid(),
  targetDate: z.string().date(),
  predictedUnitsSold: z.number().int().nonnegative(),
});
const PredictionResult = z.discriminatedUnion('predictionMode', [
  PredictionCommon.extend({
    predictionMode: z.literal('MODEL'),
    modelVersionId: z.string().uuid(),
    confidence: z.number().finite().min(0).max(100),
  }),
  PredictionCommon.extend({
    predictionMode: z.literal('COLD_START'),
    modelVersionId: z.null(),
    confidence: z.null(),
  }),
]);
type PredictionResultDto = z.infer<typeof PredictionResult>;
```

Proposed equivalent Pydantic boundary:

```python
from typing import Annotated, Literal, Union
from datetime import date
from uuid import UUID
from pydantic import BaseModel, Field

class PredictionBase(BaseModel):
    breadCategoryId: UUID
    targetDate: date
    predictedUnitsSold: int = Field(ge=0, strict=True)

class ModelPrediction(PredictionBase):
    predictionMode: Literal["MODEL"]
    modelVersionId: UUID
    confidence: float = Field(ge=0, le=100, allow_inf_nan=False)

class ColdStartPrediction(PredictionBase):
    predictionMode: Literal["COLD_START"]
    modelVersionId: None
    confidence: None

PredictionResult = Annotated[
    Union[ModelPrediction, ColdStartPrediction],
    Field(discriminator="predictionMode"),
]
```

Proposed SQL invariant sketch for the canonical `daily_predictions` table:

```sql
CHECK (
  (prediction_mode = 'MODEL'
    AND model_version_id IS NOT NULL
    AND confidence IS NOT NULL AND confidence BETWEEN 0 AND 100)
  OR
  (prediction_mode = 'COLD_START'
    AND model_version_id IS NULL AND confidence IS NULL)
)
```

`confidence` is nullable at column level; the CHECK makes it mandatory only for MODEL. Node verifies that a referenced model is valid and active at generation time. Later deactivation does not invalidate historical prediction references.

Dart DTOs retain `double? confidence` and `String? modelVersionId`, with runtime mode validation during decoding. MODEL rejects null/out-of-range confidence or absent version; COLD_START rejects any non-null confidence/version. The following is a proposed rendering example after successful decoding:

```dart
String confidenceLabel(PredictionDto value, double threshold) {
  if (value.predictionMode == PredictionMode.coldStart) {
    return 'Cold start — Low-confidence heuristic estimate';
  }
  final score = value.confidence!; // Non-null guaranteed by MODEL decoding.
  final label = score < threshold ? 'Low Confidence' : 'Model agreement';
  return '$label: ${score.toStringAsFixed(1)}%';
}
```

A dashboard average includes only MODEL values and reports its sample count. An all-cold-start selection shows Not Applicable, not 0% or a fabricated heuristic percentage.

| DTO | Required content and invariant |
|---|---|
| `PredictionRequest` | Contract version, target date, active category IDs, selected observations/origins, validated context/factors, category bases, threshold, eligible active artifact identifiers |
| `PredictionResponse` | One discriminated result per requested category, warnings and context provenance; Node verifies category/date/model correspondence |
| `TrainingRequest` | Category, selected validated observations/origins, chronological train/validation/test boundaries, feature/configuration version and candidate identity |
| `TrainingResponse` | Candidate artifact keys and hashes, data period/configuration, feature importance; no active-status claim |
| `EvaluationRequest` | Candidate/LR/current-active artifacts as applicable and the exact untouched later dataset |
| `EvaluationResponse` | MAE/RMSE/MAPE/R², sample counts, unavailable reasons, origin composition, comparison dataset fingerprint |

Dataset fingerprints describe evaluation metadata/DTOs, not a new relational entity. Node owns metadata storage.

## 6. Training, evaluation and model governance

1. An administrator initiates training. Revalidate at least 30 distinct valid daily records/category after deduplication. Insufficient data blocks training and reports the usable count.
2. Split chronologically. Configure/choose model parameters using only earlier training/validation data. Do not refit or select parameters using the final test set.
3. Fit Random Forest and Linear Regression on the same training data and evaluate them on the same test data. Retain preprocessing, feature definitions and source composition.
4. Store successfully completed artifacts as candidates and persist their metadata through Node. Training success does not change the active pointer. Incomplete artifacts/metadata cannot become a valid version.
5. Explicit evaluation records comparable metrics and provenance. To replace an active model, evaluate both candidate and current active model on the exact same chronologically later dataset, unused in either model's fitting or parameter selection.
6. On explicit activation confirmation, lock the category/model rows. Recheck valid artifacts, evaluation identity, the still-current active model and MAE. Reject candidate MAE greater than active MAE (NFR-ACC-05); equality is not a higher-MAE rejection. Missing/noncomparable/undefined primary MAE blocks replacement.
7. Atomically switch the current active row to INACTIVE and candidate to ACTIVE, retaining versions, evaluation history and actor/time audit. Enforce at most one active model/category. Any failure preserves the previous active version.
8. Restoration separately checks that the selected version is an inactive, previously active Random Forest with a retained valid evaluation and intact artifact. Following administrator confirmation, it atomically makes that version active, retains the replaced version as inactive and records a restoration audit. The report's higher-MAE rule applies to candidate activation; restoration is a distinct recovery action (Section 3.6, UC-DP-02 A4/A7/A8). Failure leaves the current active version unchanged.

First activation has no active comparator; require a valid candidate and valid evaluation but do not manufacture an active-model MAE. The report does not prescribe a particular holdout percentage, tree count or minimum test sample count; these are versioned configuration choices, subject to a nonempty valid holdout and mathematically meaningful metrics.

| Metric | Calculation/undefined handling |
|---|---|
| MAE | Mean absolute error on all test observations, including zero actuals; empty test set is unavailable |
| RMSE | Square root of mean squared error on the same complete test set |
| MAPE | Mean absolute percentage error only where actual `unitsSold > 0`; no eligible observations means null/Not Applicable and sample count 0 |
| R² | Standard residual-versus-total variance measure; insufficient samples/zero actual variance means null/Not Applicable, not a library-forced perfect score; negative values are valid |

Every simulation-derived evaluation is visibly labelled simulation-based; mixed-origin evaluation reports composition. Simulated performance is not evidence of real-world forecasting accuracy. MAPE < 10% / R² > 0.85 are optional aspirational targets if retained in research notes. They neither override the higher-MAE activation guard nor establish achieved quality.

## 7. Endpoint and user-interface plan

| Method/path | Role | Planned handling |
|---|---|---|
| `POST /api/predictions` | Manager | Manually generate the next bakery date for every active category; optional matching `targetDate`; reject duplicate date |
| `GET /api/predictions/:date` | Both, permitted data | Read stored mode/confidence/context/model details and origin-labelled comparisons |
| `GET /api/predictions/next` | Both, permitted data | Read the bakery's next date and its stored predictions for initial View state/refresh |
| `GET /api/admin/models?breadCategoryId=&page=&pageSize=` | Administrator | Paginated versions (default 20, maximum 50/page), safe metadata, origin counts and latest evaluation per version |
| `GET /api/admin/models/categories` | Administrator | Active categories for explicit candidate-training selection |
| `GET /api/admin/models/:id` | Administrator | One version's safe metadata and latest evaluation for review before a lifecycle action |
| `POST /api/admin/models/train` | Administrator | Create candidates for validated selected categories |
| `POST /api/admin/models/:id/evaluate` | Administrator | Evaluate candidate/baseline and same-test active comparison |
| `POST /api/admin/models/:id/activate` | Administrator | Explicit confirmed, guarded activation |
| `POST /api/admin/models/:id/restore` | Administrator | Explicit confirmed restoration of retained valid version |

Internal `POST /predict`, `POST /train`, `POST /evaluate` and `POST /artifacts/validate` accept Node DTOs only. `prediction.context_rules` holds configured category bases, weekday/monsoon/weather/holiday factors and explicit fallback controls; [the setup example](../../supabase/setup/prediction_context_settings.sql) starts with neutral factors and requires category bases before no-history predictions. The low-confidence threshold remains the separate `prediction.low_confidence_threshold` setting. Administrator model reads omit internal artifact paths/hashes; artifact validity is checked again during activation/restoration, not inferred from the latest stored evaluation. Latest evaluations for two versions must not be compared as if they used the same dataset unless their holdout fingerprints/periods match. Request body actor/role, active-state claims, confidence and feasibility claims are not trusted.

`PredictionView` shows next-day target date, units, mode, confidence only for MODEL, Low Confidence/heuristic wording, major factors and marked context substitutions. `ModelManagementView` shows candidate versus active/LR metrics on their identified dataset and separate Train, Evaluate, Activate and Restore actions. It never presents candidate training as immediate activation.

Low-confidence and external/system-failure events are handed to Module 1's recipient-based `NotificationService`. It applies preferences, recipient-only foreground Realtime and optional FCM delivery tracking. Opening the app may derive pending-action indicators; no indicator initiates any operation.

## 8. Implementation order and planned verification

Remaining implementation order:

1. Apply and verify the staged weather and `20261112000100_kl_holiday_sync.sql` migrations, configure the server-only OpenWeather key and bakery coordinates, and check a real next-day forecast plus a KUL year sync. Confirm that a covered date without an event is ordinary and an unavailable year uses only configured fallback or a clear error. The migration has not been applied live by this change.
2. Apply and validate the five staged candidate, evaluation, activation, restoration and prediction-persistence migrations; add artifact reconciliation if an ML artifact is saved but candidate metadata fails to commit.
3. Verify the administrator model review UI against a migrated live database, including selected-category training and retained version details before confirmation.
4. Add recipient events and reporting integration for persisted predictions and evaluations.
5. Build reporting contracts and complete the remaining verification, including performance and UAT.

| Planned check | Expected evidence |
|---|---|
| All three origins on a date; invalid actual row; duplicate same-origin row | Exactly one valid prioritized day; invalid data cannot inflate the 30-day count |
| 29 versus 30 selected days; absent/corrupt active artifact | COLD_START until both eligibility conditions hold |
| Cold-start available zeros, nonzero history, no history | Mean of observations including zero; configured base only when none; factors applied once |
| SQL/Node/Python/Dart mode mismatch fixtures | MODEL/null confidence and COLD_START/numeric confidence both rejected |
| Formula boundaries in Section 4 | Defined scores, clamping and strictly below-threshold label |
| Feature/parameter-selection audit | No future leakage or test-data use; RF/LR use identical train/test observations |
| All-zero actuals, constant actuals, single-row/empty holdout | MAPE/R² unavailable where undefined; no synthetic perfect metrics |
| Higher candidate MAE; changed active version during activation | Replacement rejected, active model retained; stale comparison re-evaluated |
| Training/storage/activation/restoration failure injection | Active version unchanged, no valid incomplete candidate, rollback of activation |
| Manager model-management request; administrator prediction request; INACTIVE profile | Permission rejected before mutation |
| Simulation-origin and mixed-origin history | Labels/composition preserved in UI, evaluation and CSV/PDF reports |
| Reference environment | Prediction within 15 seconds; applicable 50-row screen requests meet 95% within 3 seconds |

Reference environment is Android 10+, at least 4 GB RAM, stable network >=10 Mbps, available backend, up to 20 active categories and 365 daily records/category. Check UI at 360×640 through 412×915 dp. Module 6 plans >=80% independent UAT completion of login, prediction, production confirmation, simulation and leftover recording; participant count and outcomes remain unreported.
