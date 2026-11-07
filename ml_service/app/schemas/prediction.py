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


class SelectedObservationDto(StrictDto):
    id: UUID
    bread_category_id: UUID = Field(alias="breadCategoryId")
    sales_date: date = Field(alias="salesDate")
    units_sold: int = Field(alias="unitsSold", strict=True, ge=0)
    data_origin: DataOrigin = Field(alias="dataOrigin")
    source_daily_result_id: UUID | None = Field(alias="sourceDailyResultId")
    external_source_reference: str | None = Field(alias="externalSourceReference")
    context_factors: ColdStartFactorsDto | None = Field(alias="contextFactors", default=None)

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


class TrainingCandidateInput(StrictDto):
    contract_version: Literal[1] = Field(alias="contractVersion")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    rf_model_version_id: UUID = Field(alias="rfModelVersionId")
    lr_model_version_id: UUID = Field(alias="lrModelVersionId")
    holdout_start: date = Field(alias="holdoutStart")
    observations: list[SelectedObservationDto]

    @model_validator(mode="after")
    def check_chronology(self) -> "TrainingCandidateInput":
        if self.rf_model_version_id == self.lr_model_version_id:
            raise ValueError("RF and LR candidates require separate identities.")
        if len(self.observations) < 30:
            raise ValueError("At least 30 selected daily observations are required.")
        seen: set[date] = set()
        for item in self.observations:
            if item.bread_category_id != self.bread_category_id:
                raise ValueError("Training observations must match the category.")
            if item.sales_date in seen:
                raise ValueError("Training observations must have distinct dates.")
            seen.add(item.sales_date)
        if sum(day < self.holdout_start for day in seen) < 2:
            raise ValueError("At least two earlier observations are required for fitting.")
        if not any(day >= self.holdout_start for day in seen):
            raise ValueError("A chronologically later holdout is required.")
        return self


class CandidateArtifactResponse(StrictDto):
    model_version_id: UUID = Field(alias="modelVersionId")
    model_type: Literal["RANDOM_FOREST", "LINEAR_REGRESSION"] = Field(alias="modelType")
    artifact_key: str = Field(alias="artifactKey")
    sha256_hex: str = Field(alias="sha256")


class ArtifactValidationInput(StrictDto):
    contract_version: Literal[1] = Field(alias="contractVersion")
    model_version_id: UUID = Field(alias="modelVersionId")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    lifecycle_status: Literal["CANDIDATE", "INACTIVE"] = Field(alias="lifecycleStatus")
    artifact_key: str = Field(alias="artifactKey", min_length=1)
    artifact_sha256: str = Field(alias="artifactSha256", pattern=r"^[0-9a-f]{64}$")


class ArtifactValidationResponse(StrictDto):
    model_version_id: UUID = Field(alias="modelVersionId")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    valid: bool
    training_end: date | None = Field(alias="trainingEnd")
    feature_version: int | None = Field(alias="featureVersion")


class TrainingCandidateResponse(StrictDto):
    bread_category_id: UUID = Field(alias="breadCategoryId")
    training_start: date = Field(alias="trainingStart")
    training_end: date = Field(alias="trainingEnd")
    holdout_start: date = Field(alias="holdoutStart")
    fit_sample_count: int = Field(alias="fitSampleCount", ge=1)
    holdout_sample_count: int = Field(alias="holdoutSampleCount", ge=1)
    historical_context_default_count: int = Field(
        alias="historicalContextDefaultCount", ge=0
    )
    feature_version: int = Field(alias="featureVersion")
    training_fingerprint: str = Field(alias="trainingFingerprint")
    training_origins: dict[DataOrigin, int] = Field(alias="trainingOrigins")
    holdout_origins: dict[DataOrigin, int] = Field(alias="holdoutOrigins")
    candidates: list[CandidateArtifactResponse]


EvaluationRole = Literal["CANDIDATE_RF", "BASELINE_LR", "CURRENT_ACTIVE_RF"]


class EvaluationModelReferenceDto(StrictDto):
    role: EvaluationRole
    model_version_id: UUID = Field(alias="modelVersionId")
    model_type: Literal["RANDOM_FOREST", "LINEAR_REGRESSION"] = Field(alias="modelType")
    artifact_key: str = Field(alias="artifactKey", min_length=1)


class EvaluationInput(StrictDto):
    contract_version: Literal[1] = Field(alias="contractVersion")
    bread_category_id: UUID = Field(alias="breadCategoryId")
    holdout_start: date = Field(alias="holdoutStart")
    observations: list[SelectedObservationDto]
    models: list[EvaluationModelReferenceDto]

    @model_validator(mode="after")
    def check_comparison(self) -> "EvaluationInput":
        roles = [model.role for model in self.models]
        if set(roles) not in (
            {"CANDIDATE_RF", "BASELINE_LR"},
            {"CANDIDATE_RF", "BASELINE_LR", "CURRENT_ACTIVE_RF"},
        ) or len(roles) != len(set(roles)):
            raise ValueError("RF candidate and LR baseline are required once each.")
        if len({model.model_version_id for model in self.models}) != len(self.models):
            raise ValueError("Each compared model needs a distinct version.")
        for model in self.models:
            expected_type = "LINEAR_REGRESSION" if model.role == "BASELINE_LR" else "RANDOM_FOREST"
            if model.model_type != expected_type:
                raise ValueError("Comparison role and model type disagree.")

        seen: set[date] = set()
        for item in self.observations:
            if item.bread_category_id != self.bread_category_id:
                raise ValueError("Evaluation observations must match the category.")
            if item.sales_date in seen:
                raise ValueError("Evaluation observations must have distinct dates.")
            seen.add(item.sales_date)
        if not any(day < self.holdout_start for day in seen):
            raise ValueError("Earlier feature history is required.")
        if not any(day >= self.holdout_start for day in seen):
            raise ValueError("A later holdout observation is required.")
        return self


class EvaluationResultDto(StrictDto):
    role: EvaluationRole
    model_version_id: UUID = Field(alias="modelVersionId")
    model_type: Literal["RANDOM_FOREST", "LINEAR_REGRESSION"] = Field(alias="modelType")
    mae: float = Field(ge=0, allow_inf_nan=False)
    rmse: float = Field(ge=0, allow_inf_nan=False)
    mape: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    r_squared: float | None = Field(alias="rSquared", default=None, le=1, allow_inf_nan=False)
    sample_count: int = Field(alias="sampleCount", ge=1)
    mape_sample_count: int = Field(alias="mapeSampleCount", ge=0)
    mape_unavailable_reason: Literal["NO_NONZERO_ACTUALS"] | None = Field(
        alias="mapeUnavailableReason"
    )
    r_squared_unavailable_reason: Literal[
        "INSUFFICIENT_SAMPLES", "CONSTANT_ACTUALS"
    ] | None = Field(alias="rSquaredUnavailableReason")
    predictions: list["EvaluationPredictionDto"]


class EvaluationPredictionDto(StrictDto):
    sales_date: date = Field(alias="salesDate")
    predicted_units_sold: int = Field(alias="predictedUnitsSold", strict=True, ge=0)


class EvaluationResponse(StrictDto):
    bread_category_id: UUID = Field(alias="breadCategoryId")
    holdout_start: date = Field(alias="holdoutStart")
    holdout_end: date = Field(alias="holdoutEnd")
    holdout_manifest: dict = Field(alias="holdoutManifest")
    holdout_fingerprint: str = Field(alias="holdoutFingerprint")
    data_origins: list[DataOrigin] = Field(alias="dataOrigins")
    evaluation_label: Literal[
        "ACTUAL_ONLY", "IMPORTED_HISTORICAL_ONLY",
        "SIMULATION_BASED", "MIXED_NON_SIMULATION",
    ] = Field(alias="evaluationLabel")
    origin_counts: dict[DataOrigin, int] = Field(alias="originCounts")
    results: list[EvaluationResultDto]


class ColdStartPredictionResponse(StrictDto):
    bread_category_id: UUID = Field(alias="breadCategoryId")
    target_date: date = Field(alias="targetDate")
    prediction_mode: Literal["COLD_START"] = Field(alias="predictionMode")
    predicted_units_sold: int = Field(alias="predictedUnitsSold", strict=True, ge=0)
    model_version_id: None = Field(alias="modelVersionId")
    confidence: None
    low_confidence: Literal[True] = Field(alias="lowConfidence")
    confidence_label: str = Field(alias="confidenceLabel")
    reason: Literal[
        "INSUFFICIENT_HISTORY",
        "NO_ACTIVE_MODEL",
        "INVALID_ACTIVE_MODEL",
        "ARTIFACT_UNAVAILABLE",
    ]
    base_demand: float = Field(alias="baseDemand", ge=0, allow_inf_nan=False)
    base_source: Literal["OBSERVATION_MEAN", "CONFIGURED_BASE"] = Field(
        alias="baseSource"
    )


class ModelPredictionResponse(StrictDto):
    bread_category_id: UUID = Field(alias="breadCategoryId")
    target_date: date = Field(alias="targetDate")
    prediction_mode: Literal["MODEL"] = Field(alias="predictionMode")
    predicted_units_sold: int = Field(alias="predictedUnitsSold", strict=True, ge=0)
    model_version_id: UUID = Field(alias="modelVersionId")
    confidence: float = Field(ge=0, le=100, allow_inf_nan=False)
    low_confidence: bool = Field(alias="lowConfidence")
    confidence_label: str = Field(alias="confidenceLabel")
    reason: Literal["MODEL_READY"]
