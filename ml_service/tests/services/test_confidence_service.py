import math

import pytest

from app.services.confidence_service import (
    ConfidenceService,
)


def test_identical_trees_produce_full_confidence() -> None:
    result = ConfidenceService.calculate(
        [10.0, 10.0, 10.0],
    )

    assert result.predicted_units_sold == 10
    assert result.tree_mean == pytest.approx(10.0)
    assert result.tree_standard_deviation == pytest.approx(
        0.0,
    )
    assert result.confidence == pytest.approx(100.0)
    assert result.low_confidence is False


def test_report_formula_is_applied() -> None:
    result = ConfidenceService.calculate([1.0, 2.0])

    assert result.predicted_units_sold == 2
    assert result.tree_mean == pytest.approx(1.5)
    assert result.tree_standard_deviation == pytest.approx(
        0.5,
    )
    assert result.confidence == pytest.approx(
        66.6666666667,
    )
    assert result.low_confidence is True


def test_confidence_is_bounded_at_zero() -> None:
    result = ConfidenceService.calculate(
        [-10.0, 10.0],
    )

    assert result.predicted_units_sold == 0
    assert result.confidence == pytest.approx(0.0)
    assert result.low_confidence is True


def test_threshold_equality_is_not_low_confidence() -> None:
    result = ConfidenceService.calculate(
        [3.0, 5.0],
        low_confidence_threshold=75.0,
    )

    assert result.confidence == pytest.approx(75.0)
    assert result.low_confidence is False


def test_negative_mean_is_clamped_to_zero_units() -> None:
    result = ConfidenceService.calculate(
        [-1.0, -1.0],
    )

    assert result.predicted_units_sold == 0
    assert result.confidence == pytest.approx(100.0)


@pytest.mark.parametrize(
    "predictions",
    [
        [],
        [math.nan],
        [math.inf],
        [True],
    ],
)
def test_invalid_tree_predictions_are_rejected(
    predictions: list[float],
) -> None:
    with pytest.raises(ValueError):
        ConfidenceService.calculate(predictions)


@pytest.mark.parametrize(
    "threshold",
    [-0.1, 100.1, math.nan],
)
def test_invalid_threshold_is_rejected(
    threshold: float,
) -> None:
    with pytest.raises(ValueError):
        ConfidenceService.calculate(
            [10.0],
            low_confidence_threshold=threshold,
        )