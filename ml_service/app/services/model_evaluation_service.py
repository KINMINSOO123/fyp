from math import isfinite

from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression

from app.schemas.prediction import EvaluationInput, SelectedObservationDto
from app.services.confidence_service import ConfidenceService
from app.services.dataset_manifest_service import DatasetManifestService
from app.services.feature_preparation_service import FEATURE_VERSION, FeaturePreparationService
from app.services.model_artifact_store import ModelArtifactStore, StoredModel
from app.services.model_metrics_service import ModelMetricsService
from app.services.prediction_math import round_half_away_from_zero


ORIGIN_ORDER = (
    "ACTUAL_TRANSACTION", "IMPORTED_HISTORICAL", "SIMULATION_GENERATED"
)


class ModelEvaluationService:
    """Evaluate retained models on one identical, chronologically later dataset."""

    def __init__(self, store: ModelArtifactStore | None = None) -> None:
        self.store = store or ModelArtifactStore()

    def evaluate(self, request: EvaluationInput) -> dict:
        bundles: dict[str, StoredModel] = {}
        for reference in request.models:
            bundle = self.store.load(reference.artifact_key)
            if bundle is None or (
                bundle.category_id != str(request.bread_category_id)
                or bundle.model_version_id != str(reference.model_version_id)
                or bundle.model_type != reference.model_type
            ):
                raise ValueError("A compared model artifact is missing or mismatched.")
            if request.holdout_start <= bundle.training_end or (
                request.holdout_start < bundle.holdout_start
            ):
                raise ValueError("Holdout must be later than every model's fitting period.")
            bundles[reference.role] = bundle

        candidate = bundles["CANDIDATE_RF"]
        baseline = bundles["BASELINE_LR"]
        if (
            candidate.training_fingerprint != baseline.training_fingerprint
            or candidate.training_end != baseline.training_end
            or candidate.holdout_start != baseline.holdout_start
        ):
            raise ValueError("RF and LR candidates were not fitted on the same training data.")

        ordered = sorted(request.observations, key=lambda item: item.sales_date)
        training_history = [item for item in ordered if item.sales_date <= candidate.training_end]
        if DatasetManifestService.fingerprint(
            request.bread_category_id, training_history
        ) != candidate.training_fingerprint:
            raise ValueError("Candidate fitting history no longer matches the retained artifact.")

        holdout = [item for item in ordered if item.sales_date >= request.holdout_start]
        features = [
            FeaturePreparationService.for_date(
                item.sales_date,
                [prior for prior in ordered if prior.sales_date < item.sales_date],
                item.context_factors,
            )
            for item in holdout
        ]
        actual = [item.units_sold for item in holdout]
        results = []
        for reference in request.models:
            bundle = bundles[reference.role]
            predicted = self._predict(bundle, features)
            metrics = ModelMetricsService.calculate(actual, predicted)
            results.append({
                "role": reference.role,
                "modelVersionId": reference.model_version_id,
                "modelType": reference.model_type,
                "mae": metrics.mae,
                "rmse": metrics.rmse,
                "mape": metrics.mape,
                "rSquared": metrics.r_squared,
                "sampleCount": metrics.sample_count,
                "mapeSampleCount": metrics.mape_sample_count,
                "mapeUnavailableReason": metrics.mape_unavailable_reason,
                "rSquaredUnavailableReason": metrics.r_squared_unavailable_reason,
                "predictions": [
                    {"salesDate": item.sales_date, "predictedUnitsSold": value}
                    for item, value in zip(holdout, predicted, strict=True)
                ],
            })

        origins = [origin for origin in ORIGIN_ORDER if any(
            item.data_origin == origin for item in holdout
        )]
        if "SIMULATION_GENERATED" in origins:
            label = "SIMULATION_BASED"
        elif origins == ["ACTUAL_TRANSACTION"]:
            label = "ACTUAL_ONLY"
        elif origins == ["IMPORTED_HISTORICAL"]:
            label = "IMPORTED_HISTORICAL_ONLY"
        else:
            label = "MIXED_NON_SIMULATION"
        manifest = self._holdout_manifest(request, ordered, holdout)
        return {
            "breadCategoryId": request.bread_category_id,
            "holdoutStart": request.holdout_start,
            "holdoutEnd": holdout[-1].sales_date,
            "holdoutManifest": manifest,
            "holdoutFingerprint": DatasetManifestService.digest(manifest),
            "dataOrigins": origins,
            "evaluationLabel": label,
            "originCounts": {
                origin: sum(item.data_origin == origin for item in holdout)
                for origin in ORIGIN_ORDER
            },
            "results": results,
        }

    @staticmethod
    def _predict(bundle: StoredModel, features: list[list[float]]) -> list[int]:
        if bundle.model_type == "RANDOM_FOREST":
            forest = bundle.estimator
            assert isinstance(forest, RandomForestRegressor)
            return [
                ConfidenceService.calculate(
                    [float(tree.predict([row])[0]) for tree in forest.estimators_]
                ).predicted_units_sold
                for row in features
            ]
        regression = bundle.estimator
        assert isinstance(regression, LinearRegression)
        values = [float(value) for value in regression.predict(features)]
        if not all(isfinite(value) for value in values):
            raise ValueError("Model returned a nonfinite prediction.")
        return [max(0, round_half_away_from_zero(value)) for value in values]

    @staticmethod
    def _holdout_manifest(
        request: EvaluationInput,
        ordered: list[SelectedObservationDto],
        holdout: list[SelectedObservationDto],
    ) -> dict:
        return {
            "breadCategoryId": str(request.bread_category_id),
            "featureVersion": FEATURE_VERSION,
            "holdoutStart": request.holdout_start.isoformat(),
            "priorObservationIds": [str(item.id) for item in ordered
                                    if item.sales_date < request.holdout_start],
            "holdoutRows": DatasetManifestService.observations(holdout),
            "featureHistoryFingerprint": DatasetManifestService.fingerprint(
                request.bread_category_id, ordered
            ),
        }
