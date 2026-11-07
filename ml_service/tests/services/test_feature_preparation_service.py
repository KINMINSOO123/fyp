from datetime import date
from uuid import UUID

import pytest

from app.schemas.prediction import SelectedObservationDto
from app.services.feature_preparation_service import FeaturePreparationService


def item(day: int, units: int) -> SelectedObservationDto:
    return SelectedObservationDto.model_validate({
        "id": str(UUID(int=day)),
        "breadCategoryId": "00000000-0000-4000-8000-000000000001",
        "salesDate": date(2026, 10, day).isoformat(),
        "unitsSold": units,
        "dataOrigin": "ACTUAL_TRANSACTION",
        "sourceDailyResultId": None,
        "externalSourceReference": f"source-{day}",
    })


def test_t_dp_features_01_uses_only_prior_sales_and_marks_missing_context() -> None:
    """T-DP-FEAT-01: FR-DP-01, BR-DP-02."""
    prior = [item(1, 10), item(2, 20)]
    features = FeaturePreparationService.for_date(date(2026, 10, 3), prior, None)
    assert features[2] == 1  # Days since last observed sale.
    assert features[3] == 20  # Last observed units, not the target actual.
    assert features[4] == 15
    assert features[-1] == 1  # Historical context default was marked.
    with pytest.raises(ValueError, match="Future or same-day"):
        FeaturePreparationService.for_date(
            date(2026, 10, 2), prior, None
        )


def test_t_dp_features_02_later_holdout_is_not_part_of_fit_rows() -> None:
    """T-DP-FEAT-02: FR-DP-06, NFR-ACC-05."""
    observations = [item(1, 10), item(2, 20), item(3, 30), item(4, 40)]
    fit_x, fit_y, test_x, test_y = FeaturePreparationService.training_rows(
        observations, date(2026, 10, 4)
    )
    assert fit_y == [20, 30]
    assert test_y == [40]
    assert fit_x[-1][3] == 20
    assert test_x[0][3] == 30
