from collections.abc import Callable

from app.schemas.prediction import PredictionCategoryInput
from app.services.cold_start_service import ColdStartService
from app.services.confidence_service import ConfidenceService
from app.services.feature_preparation_service import FeaturePreparationService
from app.services.model_artifact_store import ModelArtifactStore
from app.services.prediction_mode_service import (
    ActiveModelReference,
    PredictionModeService,
    SelectedObservation,
)


class ModelInferenceNotReady(Exception):
    """A valid active model needs the matching feature/inference pipeline."""


class PredictionService:
    def __init__(
        self,
        store: ModelArtifactStore | None = None,
        artifact_is_valid: Callable[[ActiveModelReference], bool] | None = None,
    ) -> None:
        self.store = store or ModelArtifactStore()
        self.artifact_is_valid = (
            artifact_is_valid or self.store.is_valid_random_forest
        )

    def predict_category(self, request: PredictionCategoryInput) -> dict:
        model = request.active_model
        active_model = None if model is None else ActiveModelReference(
            model_version_id=str(model.model_version_id),
            bread_category_id=str(model.bread_category_id),
            model_type=model.model_type,
            lifecycle_status=model.lifecycle_status,
            artifact_key=model.artifact_key,
        )

        decision = PredictionModeService.choose(
            category_id=str(request.bread_category_id),
            target_date=request.target_date,
            observations=[
                SelectedObservation(
                    sales_date=item.sales_date,
                    units_sold=item.units_sold,
                    data_origin=item.data_origin,
                )
                for item in request.observations
            ],
            active_model=active_model,
            artifact_is_valid=self.artifact_is_valid,
        )

        if decision.mode == "MODEL":
            if active_model is None:
                raise ModelInferenceNotReady()
            bundle = self.store.load_random_forest(active_model)
            if bundle is None or bundle.training_end >= request.target_date:
                raise ModelInferenceNotReady()
            features = FeaturePreparationService.for_date(
                request.target_date, request.observations, request.factors
            )
            agreement = ConfidenceService.calculate(
                [float(tree.predict([features])[0])
                 for tree in bundle.estimator.estimators_],
                request.confidence_threshold,
            )
            return {
                "breadCategoryId": request.bread_category_id,
                "targetDate": request.target_date,
                "predictionMode": "MODEL",
                "predictedUnitsSold": agreement.predicted_units_sold,
                "modelVersionId": request.active_model.model_version_id,
                "confidence": agreement.confidence,
                "lowConfidence": agreement.low_confidence,
                "confidenceLabel": "Low Confidence" if agreement.low_confidence
                    else "Model agreement",
                "reason": "MODEL_READY",
            }

        result = ColdStartService.calculate(
            units_sold_observations=[item.units_sold for item in request.observations],
            configured_base_quantity=request.configured_base_quantity,
            weekday_factor=request.factors.weekday_factor,
            monsoon_factor=request.factors.monsoon_factor,
            weather_factor=request.factors.weather_factor,
            holiday_factor=request.factors.holiday_factor,
        )

        return {
            "breadCategoryId": request.bread_category_id,
            "targetDate": request.target_date,
            "predictionMode": result.prediction_mode,
            "predictedUnitsSold": result.predicted_units_sold,
            "modelVersionId": None,
            "confidence": None,
            "lowConfidence": True,
            "confidenceLabel": result.confidence_label,
            "reason": decision.reason,
            "baseDemand": result.base_demand,
            "baseSource": result.base_source,
        }
