from dataclasses import dataclass
from math import isfinite, sqrt


@dataclass(frozen=True)
class ModelMetrics:
    mae: float
    rmse: float
    mape: float | None
    r_squared: float | None
    sample_count: int
    mape_sample_count: int
    mape_unavailable_reason: str | None
    r_squared_unavailable_reason: str | None


class ModelMetricsService:
    """Compare predicted units sold with actual units sold on one holdout."""

    @staticmethod
    def calculate(actual: list[int], predicted: list[int]) -> ModelMetrics:
        if not actual or len(actual) != len(predicted):
            raise ValueError("A nonempty paired holdout is required.")
        if any(type(value) is not int or value < 0 for value in actual + predicted):
            raise ValueError("Actual and predicted units must be nonnegative integers.")

        count = len(actual)
        errors = [actual_value - predicted_value for actual_value, predicted_value
                  in zip(actual, predicted, strict=True)]
        mae = sum(abs(error) for error in errors) / count
        squared_error = sum(error * error for error in errors)
        rmse = sqrt(squared_error / count)

        positive_errors = [
            abs(error) / actual_value
            for actual_value, error in zip(actual, errors, strict=True)
            if actual_value > 0
        ]
        mape = 100 * sum(positive_errors) / len(positive_errors) if positive_errors else None
        mean_actual = sum(actual) / count
        total_variance = sum((value - mean_actual) ** 2 for value in actual)
        r_squared = 1 - squared_error / total_variance if count >= 2 and total_variance > 0 else None
        if not all(isfinite(value) for value in (mae, rmse)):
            raise ValueError("Evaluation metrics must be finite.")
        if mape is not None and not isfinite(mape):
            raise ValueError("MAPE must be finite.")
        if r_squared is not None and not isfinite(r_squared):
            raise ValueError("R-squared must be finite.")
        return ModelMetrics(
            mae=mae,
            rmse=rmse,
            mape=mape,
            r_squared=r_squared,
            sample_count=count,
            mape_sample_count=len(positive_errors),
            mape_unavailable_reason=None if positive_errors else "NO_NONZERO_ACTUALS",
            r_squared_unavailable_reason=(
                None if r_squared is not None else
                "INSUFFICIENT_SAMPLES" if count < 2 else "CONSTANT_ACTUALS"
            ),
        )
