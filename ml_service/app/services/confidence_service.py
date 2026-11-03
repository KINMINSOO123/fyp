from dataclasses import dataclass
from math import isfinite
from numbers import Real
from statistics import fmean, pstdev
from typing import Sequence
from app.services.prediction_math import (
    round_half_away_from_zero,
)

@dataclass(frozen=True)
class ConfidenceResult:
    predicted_units_sold: int
    confidence: float
    low_confidence: bool
    tree_mean: float
    tree_standard_deviation: float


class ConfidenceService:
    """Calculates tree agreement, not prediction accuracy."""

    @staticmethod
    def calculate(
        tree_predictions: Sequence[Real],
        low_confidence_threshold: float = 75.0,
    ) -> ConfidenceResult:
        predictions = ConfidenceService._validate_predictions(
            tree_predictions,
        )

        if (
            not isfinite(low_confidence_threshold)
            or low_confidence_threshold < 0
            or low_confidence_threshold > 100
        ):
            raise ValueError(
                "Low-confidence threshold must be between 0 and 100.",
            )

        tree_mean = fmean(predictions)
        tree_standard_deviation = pstdev(predictions)

        denominator = max(abs(tree_mean), 1.0)

        agreement = 1.0 - (
            tree_standard_deviation / denominator
        )

        bounded_agreement = max(
            0.0,
            min(1.0, agreement),
        )

        confidence = 100.0 * bounded_agreement

        predicted_units_sold = max(
            0,
            round_half_away_from_zero(tree_mean)
        )

        return ConfidenceResult(
            predicted_units_sold=predicted_units_sold,
            confidence=confidence,
            low_confidence=(
                confidence < low_confidence_threshold
            ),
            tree_mean=tree_mean,
            tree_standard_deviation=(
                tree_standard_deviation
            ),
        )

    @staticmethod
    def _validate_predictions(
        tree_predictions: Sequence[Real],
    ) -> list[float]:
        if not tree_predictions:
            raise ValueError(
                "At least one tree prediction is required.",
            )

        validated: list[float] = []

        for prediction in tree_predictions:
            if (
                isinstance(prediction, bool)
                or not isinstance(prediction, Real)
            ):
                raise ValueError(
                    "Tree predictions must be numerical.",
                )

            numeric_prediction = float(prediction)

            if not isfinite(numeric_prediction):
                raise ValueError(
                    "Tree predictions must be finite.",
                )

            validated.append(numeric_prediction)

        return validated
