from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression

from app.schemas.prediction import SelectedObservationDto, TrainingCandidateInput
from app.services.feature_preparation_service import (
    FEATURE_NAMES,
    FEATURE_VERSION,
    FeaturePreparationService,
)
from app.services.dataset_manifest_service import DatasetManifestService
from app.services.model_artifact_store import ModelArtifactStore, StoredModel


class ModelTrainingService:
    """Fit fixed-parameter candidates; evaluation and activation are separate."""

    def __init__(self, store: ModelArtifactStore | None = None) -> None:
        self.store = store or ModelArtifactStore()

    def train_candidates(self, request: TrainingCandidateInput) -> dict:
        ordered = sorted(request.observations, key=lambda item: item.sales_date)
        train_x, train_y, holdout_x, _ = FeaturePreparationService.training_rows(
            ordered, request.holdout_start
        )
        if not train_x or not holdout_x:
            raise ValueError("Training and later holdout features are required.")

        rf = RandomForestRegressor(
            n_estimators=64, min_samples_leaf=2, random_state=42, n_jobs=1
        )
        lr = LinearRegression()
        rf.fit(train_x, train_y)
        lr.fit(train_x, train_y)

        training_items = [
            item for item in ordered if item.sales_date < request.holdout_start
        ]
        holdout_items = [
            item for item in ordered if item.sales_date >= request.holdout_start
        ]
        training_end = training_items[-1].sales_date
        training_fingerprint = DatasetManifestService.fingerprint(
            request.bread_category_id, training_items
        )
        candidates = []
        saved_keys: list[str] = []
        try:
            for model_type, version_id, estimator in (
                ("RANDOM_FOREST", request.rf_model_version_id, rf),
                ("LINEAR_REGRESSION", request.lr_model_version_id, lr),
            ):
                saved = self.store.save_candidate(StoredModel(
                    category_id=str(request.bread_category_id),
                    model_version_id=str(version_id),
                    model_type=model_type,
                    feature_version=FEATURE_VERSION,
                    feature_names=FEATURE_NAMES,
                    training_end=training_end,
                    holdout_start=request.holdout_start,
                    training_fingerprint=training_fingerprint,
                    estimator=estimator,
                ))
                saved_keys.append(saved.artifact_key)
                candidates.append({
                    "modelVersionId": version_id,
                    "modelType": model_type,
                    "artifactKey": saved.artifact_key,
                    "sha256": saved.sha256_hex,
                })
        except Exception:
            for key in saved_keys:
                self.store.remove_candidate(key)
            raise

        return {
            "breadCategoryId": request.bread_category_id,
            "trainingStart": training_items[0].sales_date,
            "trainingEnd": training_end,
            "holdoutStart": request.holdout_start,
            "fitSampleCount": len(train_x),
            "holdoutSampleCount": len(holdout_x),
            "historicalContextDefaultCount": sum(
                item.context_factors is None for item in ordered[1:]
            ),
            "featureVersion": FEATURE_VERSION,
            "trainingFingerprint": training_fingerprint,
            "trainingOrigins": self._origin_counts(training_items),
            "holdoutOrigins": self._origin_counts(holdout_items),
            "candidates": candidates,
        }

    @staticmethod
    def _origin_counts(observations: list[SelectedObservationDto]) -> dict[str, int]:
        counts = {
            "ACTUAL_TRANSACTION": 0,
            "IMPORTED_HISTORICAL": 0,
            "SIMULATION_GENERATED": 0,
        }
        for item in observations:
            counts[item.data_origin] += 1
        return counts
