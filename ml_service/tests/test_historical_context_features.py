"""Historical features use each observation's saved factors consistently."""

from datetime import date, timedelta
from uuid import UUID

from app.schemas.prediction import SelectedObservationDto, TrainingCandidateInput
from app.services.feature_preparation_service import FeaturePreparationService
from app.services.model_artifact_store import ModelArtifactStore
from app.services.model_training_service import ModelTrainingService


def _observation(index: int, factors: dict | None) -> SelectedObservationDto:
    return SelectedObservationDto.model_validate({
        "id": str(UUID(int=index + 1)),
        "breadCategoryId": str(UUID(int=1)),
        "salesDate": (date(2026, 10, 1) + timedelta(days=index)).isoformat(),
        "unitsSold": 10 + index,
        "dataOrigin": "SIMULATION_GENERATED" if factors else "IMPORTED_HISTORICAL",
        "sourceDailyResultId": str(UUID(int=100 + index)) if factors else None,
        "externalSourceReference": None if factors else f"import-{index}",
        "contextFactors": factors,
    })


def test_t_dp_hctx_04_training_and_evaluation_share_saved_features() -> None:
    """T-DP-HCTX-04: FR-DP-01, FR-DP-06."""
    factors = {"weekdayFactor": 1.1, "monsoonFactor": 1,
               "weatherFactor": 0.95, "holidayFactor": 1.05}
    rows = [_observation(0, None), _observation(1, factors),
            _observation(2, None), _observation(3, factors)]
    train_x, _, holdout_x, _ = FeaturePreparationService.training_rows(
        rows, date(2026, 10, 4)
    )
    assert train_x[0][-5:] == [1.1, 1, 0.95, 1.05, 0]
    assert train_x[1][-5:] == [1, 1, 1, 1, 1]
    assert holdout_x[0][-5:] == [1.1, 1, 0.95, 1.05, 0]
    assert holdout_x[0] == FeaturePreparationService.for_date(
        rows[3].sales_date, rows[:3], rows[3].context_factors
    )
    # The first observation is prior history only, so one of the three
    # feature rows uses neutral defaults.
    assert sum(item.context_factors is None for item in rows[1:]) == 1


def test_t_dp_hctx_05_default_count_and_fingerprint_include_saved_context(tmp_path) -> None:
    """T-DP-HCTX-05: FR-DP-01, FR-DP-06."""
    factors = {"weekdayFactor": 1.1, "monsoonFactor": 1,
               "weatherFactor": 0.95, "holidayFactor": 1.05}
    rows = [_observation(index, factors if index in (2, 29) else None)
            for index in range(30)]
    request = TrainingCandidateInput.model_validate({
        "contractVersion": 1,
        "breadCategoryId": str(UUID(int=1)),
        "rfModelVersionId": str(UUID(int=200)),
        "lrModelVersionId": str(UUID(int=201)),
        "holdoutStart": "2026-10-25",
        "observations": [row.model_dump(by_alias=True, mode="json") for row in rows],
    })
    service = ModelTrainingService(ModelArtifactStore(tmp_path))
    saved = service.train_candidates(request)
    assert saved["historicalContextDefaultCount"] == 27
    assert saved["featureVersion"] == 1
    neutral = request.model_copy(update={
        "observations": [_observation(index, None) for index in range(30)],
        "rf_model_version_id": UUID(int=202),
        "lr_model_version_id": UUID(int=203),
    })
    neutral_saved = service.train_candidates(neutral)
    assert neutral_saved["trainingFingerprint"] != saved["trainingFingerprint"]
