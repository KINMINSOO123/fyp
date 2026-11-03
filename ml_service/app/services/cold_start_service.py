from dataclasses import dataclass
from math import isfinite
from numbers import Real
from statistics import fmean
from typing import Literal, Sequence

from app.services.prediction_math import (
    round_half_away_from_zero,
)


@dataclass(frozen=True)
class ColdStartResult:
    predicted_units_sold: int
    prediction_mode: Literal["COLD_START"]
    confidence: None
    low_confidence: bool
    confidence_label: str
    base_demand: float
    base_source: Literal[
        "OBSERVATION_MEAN",
        "CONFIGURED_BASE",
    ]
    weekday_factor: float
    monsoon_factor: float
    weather_factor: float
    holiday_factor: float


class ColdStartService:
    @staticmethod
    def calculate(
        units_sold_observations: Sequence[Real],
        configured_base_quantity: Real | None,
        weekday_factor: Real,
        monsoon_factor: Real,
        weather_factor: Real,
        holiday_factor: Real,
    ) -> ColdStartResult:
        observations = (
            ColdStartService._validate_observations(
                units_sold_observations,
            )
        )

        factors = {
            "weekday_factor": ColdStartService._validate_factor(
                weekday_factor,
                "weekday factor",
            ),
            "monsoon_factor": ColdStartService._validate_factor(
                monsoon_factor,
                "monsoon factor",
            ),
            "weather_factor": ColdStartService._validate_factor(
                weather_factor,
                "weather factor",
            ),
            "holiday_factor": ColdStartService._validate_factor(
                holiday_factor,
                "holiday factor",
            ),
        }

        if observations:
            base_demand = fmean(observations)
            base_source = "OBSERVATION_MEAN"
        else:
            base_demand = ColdStartService._validate_base_quantity(
                configured_base_quantity,
            )
            base_source = "CONFIGURED_BASE"

        contextualised_demand = (
            base_demand
            * factors["weekday_factor"]
            * factors["monsoon_factor"]
            * factors["weather_factor"]
            * factors["holiday_factor"]
        )

        if not isfinite(contextualised_demand):
            raise ValueError(
                "Cold-start prediction must be finite.",
            )

        predicted_units_sold = max(
            0,
            round_half_away_from_zero(
                contextualised_demand,
            ),
        )

        return ColdStartResult(
            predicted_units_sold=predicted_units_sold,
            prediction_mode="COLD_START",
            confidence=None,
            low_confidence=True,
            confidence_label=(
                "Low Confidence - Cold-Start Heuristic"
            ),
            base_demand=base_demand,
            base_source=base_source,
            weekday_factor=factors["weekday_factor"],
            monsoon_factor=factors["monsoon_factor"],
            weather_factor=factors["weather_factor"],
            holiday_factor=factors["holiday_factor"],
        )

    @staticmethod
    def _validate_observations(
        observations: Sequence[Real],
    ) -> list[float]:
        validated: list[float] = []

        for observation in observations:
            if (
                isinstance(observation, bool)
                or not isinstance(observation, Real)
            ):
                raise ValueError(
                    "Units-sold observations must be numerical.",
                )

            numeric_observation = float(observation)

            if (
                not isfinite(numeric_observation)
                or numeric_observation < 0
            ):
                raise ValueError(
                    "Units-sold observations must be finite and nonnegative.",
                )

            validated.append(numeric_observation)

        return validated

    @staticmethod
    def _validate_base_quantity(
        value: Real | None,
    ) -> float:
        if (
            value is None
            or isinstance(value, bool)
            or not isinstance(value, Real)
        ):
            raise ValueError(
                "A configured base quantity is required when no observations exist.",
            )

        numeric_value = float(value)

        if not isfinite(numeric_value) or numeric_value < 0:
            raise ValueError(
                "Configured base quantity must be finite and nonnegative.",
            )

        return numeric_value

    @staticmethod
    def _validate_factor(
        value: Real,
        name: str,
    ) -> float:
        if (
            isinstance(value, bool)
            or not isinstance(value, Real)
        ):
            raise ValueError(
                f"{name.capitalize()} must be numerical.",
            )

        numeric_value = float(value)

        if not isfinite(numeric_value) or numeric_value < 0:
            raise ValueError(
                f"{name.capitalize()} must be finite and nonnegative.",
            )

        return numeric_value