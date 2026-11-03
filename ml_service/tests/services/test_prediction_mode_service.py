from datetime import date, timedelta

import pytest

from app.services.prediction_mode_service import (
    ActiveModelReference,
    PredictionModeService,
    SelectedObservation,
)


TARGET = date(2026, 11, 4)
MODEL = ActiveModelReference(
    model_version_id="model-1",
    bread_category_id="bread-a",
    model_type="RANDOM_FOREST",
    lifecycle_status="ACTIVE",
    artifact_key="models/bread-a/model-1.joblib",
)


def history(days: int) -> list[SelectedObservation]:
    return [
        SelectedObservation(
            sales_date=TARGET - timedelta(days=days - index),
            units_sold=0 if index == 0 else index,
            data_origin="ACTUAL_TRANSACTION"
            if index % 2 == 0
            else "SIMULATION_GENERATED",
        )
        for index in range(days)
    ]


def test_29_days_stays_cold_start_even_with_active_model() -> None:
    """T-DP-MODE-01: BR-DP-03, FR-DP-07."""
    artifact_checked = False

    def check_artifact(_: ActiveModelReference) -> bool:
        nonlocal artifact_checked
        artifact_checked = True
        return True

    decision = PredictionModeService.choose(
        category_id="bread-a",
        target_date=TARGET,
        observations=history(29),
        active_model=MODEL,
        artifact_is_valid=check_artifact,
    )
    assert decision.mode == "COLD_START"
    assert decision.reason == "INSUFFICIENT_HISTORY"
    assert decision.model_version_id is None
    assert decision.distinct_day_count == 29
    assert artifact_checked is False


def test_30_days_and_valid_active_rf_selects_model() -> None:
    """T-DP-MODE-02: BR-DP-03, FR-DP-06."""
    decision = PredictionModeService.choose(
        category_id="bread-a",
        target_date=TARGET,
        observations=history(30),
        active_model=MODEL,
        artifact_is_valid=lambda model: model.artifact_key == MODEL.artifact_key,
    )
    assert decision.mode == "MODEL"
    assert decision.reason == "MODEL_READY"
    assert decision.model_version_id == "model-1"
    assert decision.distinct_day_count == 30


def test_30_days_without_active_model_stays_cold_start() -> None:
    """T-DP-MODE-03: BR-DP-03, FR-DP-07."""
    decision = PredictionModeService.choose(
        category_id="bread-a",
        target_date=TARGET,
        observations=history(30),
        active_model=None,
        artifact_is_valid=lambda _: True,
    )
    assert decision.mode == "COLD_START"
    assert decision.reason == "NO_ACTIVE_MODEL"
    assert decision.model_version_id is None


@pytest.mark.parametrize(
    "model",
    [
        ActiveModelReference("model-1", "other-bread", "RANDOM_FOREST", "ACTIVE", "key"),
        ActiveModelReference("model-1", "bread-a", "LINEAR_REGRESSION", "ACTIVE", "key"),
        ActiveModelReference("model-1", "bread-a", "RANDOM_FOREST", "CANDIDATE", "key"),
        ActiveModelReference("model-1", "bread-a", "RANDOM_FOREST", "ACTIVE", ""),
    ],
)
def test_wrong_category_type_status_or_key_stays_cold_start(
    model: ActiveModelReference,
) -> None:
    """T-DP-MODE-04: BR-DP-03, FR-DP-06."""
    decision = PredictionModeService.choose(
        category_id="bread-a",
        target_date=TARGET,
        observations=history(30),
        active_model=model,
        artifact_is_valid=lambda _: True,
    )
    assert decision.reason == "INVALID_ACTIVE_MODEL"
    assert decision.model_version_id is None


def test_missing_or_corrupt_artifact_stays_cold_start() -> None:
    """T-DP-MODE-05: BR-DP-03, FR-DP-06."""
    for checker in (
        lambda _: False,
        lambda _: (_ for _ in ()).throw(FileNotFoundError("missing")),
    ):
        decision = PredictionModeService.choose(
            category_id="bread-a",
            target_date=TARGET,
            observations=history(30),
            active_model=MODEL,
            artifact_is_valid=checker,
        )
        assert decision.mode == "COLD_START"
        assert decision.reason == "ARTIFACT_UNAVAILABLE"
        assert decision.model_version_id is None


def test_duplicate_or_future_history_is_rejected() -> None:
    """T-DP-MODE-06: FR-DP-01, BR-DP-02."""
    duplicate = history(1) * 2
    with pytest.raises(ValueError, match="distinct dates"):
        PredictionModeService.choose(
            category_id="bread-a",
            target_date=TARGET,
            observations=duplicate,
            active_model=MODEL,
            artifact_is_valid=lambda _: True,
        )

    with pytest.raises(ValueError, match="precede"):
        PredictionModeService.choose(
            category_id="bread-a",
            target_date=TARGET,
            observations=[SelectedObservation(TARGET, 1, "ACTUAL_TRANSACTION")],
            active_model=MODEL,
            artifact_is_valid=lambda _: True,
        )


def test_invalid_units_or_origin_is_rejected() -> None:
    """T-DP-MODE-07: FR-DP-01, BR-DP-04."""
    for observation in (
        SelectedObservation(TARGET - timedelta(days=1), -1, "ACTUAL_TRANSACTION"),
        SelectedObservation(TARGET - timedelta(days=1), True, "ACTUAL_TRANSACTION"),
        SelectedObservation(TARGET - timedelta(days=1), 1, "OTHER"),
    ):
        with pytest.raises(ValueError):
            PredictionModeService.choose(
                category_id="bread-a",
                target_date=TARGET,
                observations=[observation],
                active_model=MODEL,
                artifact_is_valid=lambda _: True,
            )
