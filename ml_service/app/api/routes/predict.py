import hmac
import os

from fastapi import APIRouter, Depends, Header, HTTPException

from app.schemas.prediction import (
    ArtifactValidationInput,
    ArtifactValidationResponse,
    ColdStartPredictionResponse,
    EvaluationInput,
    EvaluationResponse,
    ModelPredictionResponse,
    PredictionCategoryInput,
    TrainingCandidateInput,
    TrainingCandidateResponse,
)
from app.services.model_training_service import ModelTrainingService
from app.services.model_evaluation_service import ModelEvaluationService
from app.services.model_artifact_store import ModelArtifactStore
from app.services.prediction_mode_service import ActiveModelReference
from app.services.prediction_service import ModelInferenceNotReady, PredictionService


router = APIRouter(tags=["Prediction"])


def require_internal_token(
    token: str | None = Header(default=None, alias="X-ML-Internal-Token"),
) -> None:
    expected = os.environ.get("ML_INTERNAL_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail={"code": "ML_NOT_CONFIGURED"})
    if token is None or not hmac.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail={"code": "ML_UNAUTHORIZED"})


def get_prediction_service() -> PredictionService:
    return PredictionService()


def get_training_service() -> ModelTrainingService:
    return ModelTrainingService()


def get_evaluation_service() -> ModelEvaluationService:
    return ModelEvaluationService()


def get_artifact_store() -> ModelArtifactStore:
    return ModelArtifactStore()


@router.post("/predict", response_model=ColdStartPredictionResponse | ModelPredictionResponse)
def predict(
    request: PredictionCategoryInput,
    _: None = Depends(require_internal_token),
    service: PredictionService = Depends(get_prediction_service),
) -> ColdStartPredictionResponse | ModelPredictionResponse:
    try:
        result = service.predict_category(request)
    except ModelInferenceNotReady as error:
        raise HTTPException(
            status_code=503,
            detail={"code": "MODEL_INFERENCE_NOT_READY"},
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail={"code": "INVALID_PREDICTION_INPUT"},
        ) from error
    if result["predictionMode"] == "MODEL":
        return ModelPredictionResponse.model_validate(result)
    return ColdStartPredictionResponse.model_validate(result)


@router.post("/train", response_model=TrainingCandidateResponse)
def train(
    request: TrainingCandidateInput,
    _: None = Depends(require_internal_token),
    service: ModelTrainingService = Depends(get_training_service),
) -> TrainingCandidateResponse:
    try:
        result = service.train_candidates(request)
    except FileExistsError as error:
        raise HTTPException(
            status_code=409, detail={"code": "CANDIDATE_ALREADY_EXISTS"}
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=422, detail={"code": "INVALID_TRAINING_INPUT"}
        ) from error
    except OSError as error:
        raise HTTPException(
            status_code=503, detail={"code": "MODEL_STORAGE_UNAVAILABLE"}
        ) from error
    return TrainingCandidateResponse.model_validate(result)


@router.post("/evaluate", response_model=EvaluationResponse)
def evaluate(
    request: EvaluationInput,
    _: None = Depends(require_internal_token),
    service: ModelEvaluationService = Depends(get_evaluation_service),
) -> EvaluationResponse:
    try:
        result = service.evaluate(request)
    except ValueError as error:
        raise HTTPException(
            status_code=422, detail={"code": "INVALID_EVALUATION_INPUT"}
        ) from error
    return EvaluationResponse.model_validate(result)


@router.post("/artifacts/validate", response_model=ArtifactValidationResponse)
def validate_artifact(
    request: ArtifactValidationInput,
    _: None = Depends(require_internal_token),
    store: ModelArtifactStore = Depends(get_artifact_store),
) -> ArtifactValidationResponse:
    reference = ActiveModelReference(
        model_version_id=str(request.model_version_id),
        bread_category_id=str(request.bread_category_id),
        model_type="RANDOM_FOREST",
        lifecycle_status=request.lifecycle_status,
        artifact_key=request.artifact_key,
    )
    bundle = store.verify_random_forest(reference, request.artifact_sha256)
    return ArtifactValidationResponse.model_validate({
        "modelVersionId": request.model_version_id,
        "breadCategoryId": request.bread_category_id,
        "valid": bundle is not None,
        "trainingEnd": bundle.training_end if bundle else None,
        "featureVersion": bundle.feature_version if bundle else None,
    })
