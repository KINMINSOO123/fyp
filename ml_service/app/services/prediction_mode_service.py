from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date
from typing import Literal


DataOrigin = Literal[
    "ACTUAL_TRANSACTION",
    "IMPORTED_HISTORICAL",
    "SIMULATION_GENERATED",
]
PredictionMode = Literal["MODEL", "COLD_START"]
DecisionReason = Literal[
    "MODEL_READY",
    "INSUFFICIENT_HISTORY",
    "NO_ACTIVE_MODEL",
    "INVALID_ACTIVE_MODEL",
    "ARTIFACT_UNAVAILABLE",
]


@dataclass(frozen=True)
class SelectedObservation:
    sales_date: date
    units_sold: int
    data_origin: DataOrigin


@dataclass(frozen=True)
class ActiveModelReference:
    model_version_id: str
    bread_category_id: str
    model_type: str
    lifecycle_status: str
    artifact_key: str


@dataclass(frozen=True)
class PredictionModeDecision:
    mode: PredictionMode
    reason: DecisionReason
    distinct_day_count: int
    model_version_id: str | None


class PredictionModeService:
    """Choose eligibility only; model inference and persistence happen later."""

    minimum_observations = 30

    @classmethod
    def choose(
        cls,
        *,
        category_id: str,
        target_date: date,
        observations: Sequence[SelectedObservation],
        active_model: ActiveModelReference | None,
        artifact_is_valid: Callable[[ActiveModelReference], bool],
    ) -> PredictionModeDecision:
        if not category_id.strip() or type(target_date) is not date:
            raise ValueError("A category and target date are required.")

        seen_dates: set[date] = set()
        for observation in observations:
            if type(observation.sales_date) is not date:
                raise ValueError("Observation date is invalid.")
            if observation.sales_date >= target_date:
                raise ValueError("Observation must precede the target date.")
            if observation.sales_date in seen_dates:
                raise ValueError("Observations must have distinct dates.")
            if type(observation.units_sold) is not int or observation.units_sold < 0:
                raise ValueError("Units sold must be a nonnegative integer.")
            if observation.data_origin not in (
                "ACTUAL_TRANSACTION",
                "IMPORTED_HISTORICAL",
                "SIMULATION_GENERATED",
            ):
                raise ValueError("Observation origin is invalid.")
            seen_dates.add(observation.sales_date)

        count = len(seen_dates)
        if count < cls.minimum_observations:
            return cls._cold_start("INSUFFICIENT_HISTORY", count)

        if active_model is None:
            return cls._cold_start("NO_ACTIVE_MODEL", count)

        if (
            active_model.bread_category_id != category_id
            or active_model.model_type != "RANDOM_FOREST"
            or active_model.lifecycle_status != "ACTIVE"
            or not active_model.model_version_id.strip()
            or not active_model.artifact_key.strip()
        ):
            return cls._cold_start("INVALID_ACTIVE_MODEL", count)

        try:
            valid_artifact = artifact_is_valid(active_model)
        except (OSError, ValueError):
            valid_artifact = False

        if not valid_artifact:
            return cls._cold_start("ARTIFACT_UNAVAILABLE", count)

        return PredictionModeDecision(
            mode="MODEL",
            reason="MODEL_READY",
            distinct_day_count=count,
            model_version_id=active_model.model_version_id,
        )

    @staticmethod
    def _cold_start(
        reason: DecisionReason,
        count: int,
    ) -> PredictionModeDecision:
        return PredictionModeDecision(
            mode="COLD_START",
            reason=reason,
            distinct_day_count=count,
            model_version_id=None,
        )
