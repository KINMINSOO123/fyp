from datetime import date
from statistics import fmean

from app.schemas.prediction import ColdStartFactorsDto, SelectedObservationDto


FEATURE_VERSION = 1
FEATURE_NAMES = (
    "weekday", "month", "days_since_last_observation", "last_observed_units",
    "mean_last_7_observations", "same_weekday_mean",
    "weekday_factor", "monsoon_factor", "weather_factor", "holiday_factor",
    "historical_context_defaulted",
)


class FeaturePreparationService:
    """Prepare one-step-ahead features using only sales dated before the target."""

    @staticmethod
    def for_date(
        target_date: date,
        prior: list[SelectedObservationDto],
        factors: ColdStartFactorsDto | None,
    ) -> list[float]:
        if not prior:
            raise ValueError("At least one earlier observation is required for model features.")
        if any(item.sales_date >= target_date for item in prior):
            raise ValueError("Future or same-day sales cannot enter model features.")

        ordered = sorted(prior, key=lambda item: item.sales_date)
        if len({item.sales_date for item in ordered}) != len(ordered):
            raise ValueError("Feature history must contain distinct dates.")
        latest = ordered[-1]
        same_weekday = [
            item.units_sold for item in ordered
            if item.sales_date.weekday() == target_date.weekday()
        ]
        context = factors or ColdStartFactorsDto.model_validate({
            "weekdayFactor": 1, "monsoonFactor": 1,
            "weatherFactor": 1, "holidayFactor": 1,
        })
        return [
            float(target_date.weekday()),
            float(target_date.month),
            float((target_date - latest.sales_date).days),
            float(latest.units_sold),
            fmean(item.units_sold for item in ordered[-7:]),
            fmean(same_weekday) if same_weekday else fmean(
                item.units_sold for item in ordered[-7:]
            ),
            context.weekday_factor,
            context.monsoon_factor,
            context.weather_factor,
            context.holiday_factor,
            float(factors is None),
        ]

    @classmethod
    def training_rows(
        cls,
        observations: list[SelectedObservationDto],
        holdout_start: date,
    ) -> tuple[list[list[float]], list[int], list[list[float]], list[int]]:
        ordered = sorted(observations, key=lambda item: item.sales_date)
        train_x: list[list[float]] = []
        train_y: list[int] = []
        holdout_x: list[list[float]] = []
        holdout_y: list[int] = []
        for index, item in enumerate(ordered):
            if index == 0:
                continue
            features = cls.for_date(
                item.sales_date, ordered[:index], item.context_factors
            )
            if item.sales_date < holdout_start:
                train_x.append(features)
                train_y.append(item.units_sold)
            else:
                holdout_x.append(features)
                holdout_y.append(item.units_sold)
        return train_x, train_y, holdout_x, holdout_y
