import pytest

from app.services.model_metrics_service import ModelMetricsService


def test_t_dp_eval_01_metrics_compare_predicted_with_actual_units_sold() -> None:
    """T-DP-EVAL-01: FR-DP-06, NFR-ACC-05."""
    metrics = ModelMetricsService.calculate([0, 10, 20], [2, 8, 18])
    assert metrics.mae == 2
    assert metrics.rmse == 2
    assert metrics.mape == pytest.approx(15)
    assert metrics.r_squared == pytest.approx(0.94)
    assert metrics.sample_count == 3
    assert metrics.mape_sample_count == 2


def test_t_dp_eval_02_undefined_metrics_are_null_not_perfect() -> None:
    """T-DP-EVAL-02: FR-DP-06, NFR-ACC-05."""
    all_zero = ModelMetricsService.calculate([0, 0], [1, 2])
    assert all_zero.mae == 1.5
    assert all_zero.mape is None
    assert all_zero.mape_sample_count == 0
    assert all_zero.mape_unavailable_reason == "NO_NONZERO_ACTUALS"
    assert all_zero.r_squared is None
    assert all_zero.r_squared_unavailable_reason == "CONSTANT_ACTUALS"

    single = ModelMetricsService.calculate([5], [7])
    assert single.r_squared is None
    assert single.r_squared_unavailable_reason == "INSUFFICIENT_SAMPLES"


def test_t_dp_eval_03_negative_r_squared_and_invalid_pairs() -> None:
    """T-DP-EVAL-03: FR-DP-06."""
    assert ModelMetricsService.calculate([10, 20], [100, 100]).r_squared < 0
    with pytest.raises(ValueError, match="paired"):
        ModelMetricsService.calculate([1], [])
