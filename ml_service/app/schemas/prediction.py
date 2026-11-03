from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


DataOrigin = Literal[
    "ACTUAL_TRANSACTION",
    "IMPORTED_HISTORICAL",
    "SIMULATION_GENERATED",
]


class StrictDto(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=False)


class SelectedObservationDto(StrictDto):
    id: UUID
    bread_category_id: UUID = Field(alias="breadCategoryId")
    sales_date: date = Field(alias="salesDate")
    units_sold: int = Field(alias="unitsSold", strict=True, ge=0)
    data_origin: DataOrigin = Field(alias="dataOrigin")
    source_daily_result_id: UUID | None = Field(alias="sourceDailyResultId")
    external_source_reference: str | None = Field(alias="externalSourceReference")

    @model_validator(mode="after")
    def check_origin_source(self) -> "SelectedObservationDto":
        if self.data_origin == "SIMULATION_GENERATED":
            if (
                self.source_daily_result_id is None
                or self.external_source_reference is not None
            ):
                raise ValueError("Simulation history requires a daily result source.")
        elif (
            self.source_daily_result_id is not None
            or not self.external_source_reference
            or not self.external_source_reference.strip()
        ):
            raise ValueError("Actual/imported history requires an external source.")
        return self


class ColdStartFactorsDto(StrictDto):
    weekday_factor: float = Field(alias="weekdayFactor", ge=0, allow_inf_nan=False)
    monsoon_factor: float = Field(alias="monsoonFactor", ge=0, allow_inf_nan=False)
    weather_factor: float = Field(alias="weatherFactor", ge=0, allow_inf_nan=False)
    holiday_factor: float = Field(alias="holidayFactor", ge=0, allow_inf_nan=False)

    @field_validator(
        "weekday_factor", "monsoon_factor", "weather_factor", "holiday_factor",
        mode="before",
    )
    @classmethod
    def reject_boolean_factor(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("A factor must be numerical.")
        return value


class ActiveModelDto(StrictDto):
    model_version_id: UUID = Field(alias="modelVersionId")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    model_type: str = Field(alias="modelType")
    lifecycle_status: str = Field(alias="lifecycleStatus")
    artifact_key: str = Field(alias="artifactKey")


class PredictionCategoryInput(StrictDto):
    contract_version: Literal[1] = Field(alias="contractVersion")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    target_date: date = Field(alias="targetDate")
    observations: list[SelectedObservationDto]
    configured_base_quantity: float | None = Field(
        alias="configuredBaseQuantity", default=None, ge=0, allow_inf_nan=False
    )
    factors: ColdStartFactorsDto
    confidence_threshold: float = Field(
        alias="confidenceThreshold", ge=0, le=100, allow_inf_nan=False
    )
    active_model: ActiveModelDto | None = Field(alias="activeModel", default=None)

    @field_validator("configured_base_quantity", "confidence_threshold", mode="before")
    @classmethod
    def reject_boolean_quantity(cls, value: object) -> object:
        if isinstance(value, bool):
            raise ValueError("A quantity or threshold must be numerical.")
        return value

    @model_validator(mode="after")
    def check_history(self) -> "PredictionCategoryInput":
        seen_dates: set[date] = set()
        for observation in self.observations:
            if observation.bread_category_id != self.bread_category_id:
                raise ValueError("Observation belongs to another category.")
            if observation.sales_date >= self.target_date:
                raise ValueError("Observation must precede the target date.")
            if observation.sales_date in seen_dates:
                raise ValueError("Only one selected observation per date is allowed.")
            seen_dates.add(observation.sales_date)

        if not self.observations and self.configured_base_quantity is None:
            raise ValueError("A configured base is required without history.")
        return self
