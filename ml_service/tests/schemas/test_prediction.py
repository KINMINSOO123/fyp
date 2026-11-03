from uuid import UUID

import pytest
from pydantic import ValidationError

from app.schemas.prediction import PredictionCategoryInput


CATEGORY = "00000000-0000-4000-8000-000000000001"
RESULT = "00000000-0000-4000-8000-000000000002"
OBSERVATION = "00000000-0000-4000-8000-000000000003"


def request() -> dict:
    return {
        "contractVersion": 1,
        "breadCategoryId": CATEGORY,
        "targetDate": "2026-11-04",
        "observations": [{
            "id": OBSERVATION,
            "breadCategoryId": CATEGORY,
            "salesDate": "2026-11-03",
            "unitsSold": 0,
            "dataOrigin": "SIMULATION_GENERATED",
            "sourceDailyResultId": RESULT,
            "externalSourceReference": None,
        }],
        "configuredBaseQuantity": None,
        "factors": {
            "weekdayFactor": 1,
            "monsoonFactor": 1.1,
            "weatherFactor": 0.9,
            "holidayFactor": 1,
        },
        "confidenceThreshold": 75,
        "activeModel": None,
    }


def test_t_dp_dto_01_accepts_selected_zero_sales_and_origin() -> None:
    """T-DP-DTO-01: FR-DP-01, BR-DP-04, NFR-ACC-07."""
    parsed = PredictionCategoryInput.model_validate(request())
    assert parsed.observations[0].units_sold == 0
    assert parsed.observations[0].data_origin == "SIMULATION_GENERATED"
    assert parsed.bread_category_id == UUID(CATEGORY)


def test_t_dp_dto_02_rejects_duplicate_or_future_days() -> None:
    """T-DP-DTO-02: FR-DP-01, BR-DP-02."""
    duplicate = request()
    duplicate["observations"].append(dict(duplicate["observations"][0]))
    with pytest.raises(ValidationError, match="one selected observation"):
        PredictionCategoryInput.model_validate(duplicate)

    future = request()
    future["observations"][0]["salesDate"] = "2026-11-04"
    with pytest.raises(ValidationError, match="precede"):
        PredictionCategoryInput.model_validate(future)


def test_t_dp_dto_03_rejects_wrong_category_or_source() -> None:
    """T-DP-DTO-03: FR-DP-01."""
    wrong_category = request()
    wrong_category["observations"][0]["breadCategoryId"] = RESULT
    with pytest.raises(ValidationError, match="another category"):
        PredictionCategoryInput.model_validate(wrong_category)

    wrong_source = request()
    wrong_source["observations"][0]["sourceDailyResultId"] = None
    with pytest.raises(ValidationError, match="daily result source"):
        PredictionCategoryInput.model_validate(wrong_source)


def test_t_dp_dto_04_rejects_invalid_quantities_factors_and_unknown_fields() -> None:
    """T-DP-DTO-04: FR-DP-01, NFR-DAT-01."""
    negative = request()
    negative["observations"][0]["unitsSold"] = -1
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(negative)

    boolean = request()
    boolean["observations"][0]["unitsSold"] = True
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(boolean)

    bad_factor = request()
    bad_factor["factors"]["weatherFactor"] = -0.1
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(bad_factor)

    boolean_factor = request()
    boolean_factor["factors"]["weatherFactor"] = True
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(boolean_factor)

    invented_target = request()
    invented_target["estimatedDemand"] = 100
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(invented_target)


def test_t_dp_dto_05_requires_base_when_no_history() -> None:
    """T-DP-DTO-05: FR-DP-07."""
    no_history = request()
    no_history["observations"] = []
    with pytest.raises(ValidationError, match="configured base"):
        PredictionCategoryInput.model_validate(no_history)

    no_history["configuredBaseQuantity"] = 10
    parsed = PredictionCategoryInput.model_validate(no_history)
    assert parsed.configured_base_quantity == 10


def test_t_dp_dto_06_rejects_unknown_contract_version() -> None:
    """T-DP-DTO-06: FR-DP-05."""
    wrong_version = request()
    wrong_version["contractVersion"] = 2
    with pytest.raises(ValidationError):
        PredictionCategoryInput.model_validate(wrong_version)
