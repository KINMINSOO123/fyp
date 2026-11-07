from datetime import date, timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from app.api.routes.predict import (
    get_artifact_store, get_prediction_service, get_training_service,
)
from app.main import app
from app.services.model_artifact_store import ModelArtifactStore
from app.services.model_training_service import ModelTrainingService
from app.services.prediction_service import PredictionService


CATEGORY = "00000000-0000-4000-8000-000000000001"
MODEL = "00000000-0000-4000-8000-000000000002"
RESULT = "00000000-0000-4000-8000-000000000003"
TARGET = date(2026, 11, 4)


def observation(index: int, units: int) -> dict:
    return {
        "id": str(UUID(int=100 + index)),
        "breadCategoryId": CATEGORY,
        "salesDate": (TARGET - timedelta(days=index + 1)).isoformat(),
        "unitsSold": units,
        "dataOrigin": "SIMULATION_GENERATED",
        "sourceDailyResultId": RESULT,
        "externalSourceReference": None,
    }


def payload(days: int = 2) -> dict:
    return {
        "contractVersion": 1,
        "breadCategoryId": CATEGORY,
        "targetDate": TARGET.isoformat(),
        "observations": [observation(i, 10 + 4 * i) for i in range(days)],
        "configuredBaseQuantity": 20,
        "factors": {
            "weekdayFactor": 1,
            "monsoonFactor": 1,
            "weatherFactor": 1,
            "holidayFactor": 1,
        },
        "confidenceThreshold": 75,
        "activeModel": None,
    }


def test_t_dp_api_01_cold_start_uses_units_sold_mean_and_null_confidence(monkeypatch) -> None:
    """T-DP-API-01: FR-DP-07, NFR-ACC-08."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    response = TestClient(app).post(
        "/predict", json=payload(), headers={"X-ML-Internal-Token": "test-only-secret"}
    )
    assert response.status_code == 200
    result = response.json()
    assert result["predictedUnitsSold"] == 12
    assert result["baseDemand"] == 12
    assert result["baseSource"] == "OBSERVATION_MEAN"
    assert result["predictionMode"] == "COLD_START"
    assert result["confidence"] is None
    assert result["modelVersionId"] is None
    assert result["lowConfidence"] is True


def test_t_dp_api_02_no_history_uses_configured_base_and_factors(monkeypatch) -> None:
    """T-DP-API-02: FR-DP-07."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    request = payload(0)
    request["factors"]["weekdayFactor"] = 1.2
    request["factors"]["weatherFactor"] = 0.8
    response = TestClient(app).post(
        "/predict", json=request, headers={"X-ML-Internal-Token": "test-only-secret"}
    )
    assert response.status_code == 200
    assert response.json()["predictedUnitsSold"] == 19
    assert response.json()["baseSource"] == "CONFIGURED_BASE"


def test_t_dp_api_03_30_days_without_active_model_remains_cold_start(monkeypatch) -> None:
    """T-DP-API-03: BR-DP-03, FR-DP-07."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    response = TestClient(app).post(
        "/predict", json=payload(30),
        headers={"X-ML-Internal-Token": "test-only-secret"},
    )
    assert response.status_code == 200
    assert response.json()["reason"] == "NO_ACTIVE_MODEL"
    assert response.json()["confidence"] is None


def test_t_dp_api_04_training_and_active_rf_inference(monkeypatch, tmp_path) -> None:
    """T-DP-API-04: BR-DP-03, FR-DP-06, NFR-ACC-08."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    store = ModelArtifactStore(tmp_path)
    app.dependency_overrides[get_training_service] = lambda: ModelTrainingService(store)
    app.dependency_overrides[get_prediction_service] = lambda: PredictionService(store)
    app.dependency_overrides[get_artifact_store] = lambda: store
    try:
        training = {
            "contractVersion": 1,
            "breadCategoryId": CATEGORY,
            "rfModelVersionId": MODEL,
            "lrModelVersionId": "00000000-0000-4000-8000-000000000004",
            "holdoutStart": "2026-10-29",
            "observations": payload(30)["observations"],
        }
        client = TestClient(app)
        trained = client.post(
            "/train", json=training,
            headers={"X-ML-Internal-Token": "test-only-secret"},
        )
        assert trained.status_code == 200, trained.text
        result = trained.json()
        assert result["fitSampleCount"] == 23
        assert result["holdoutSampleCount"] == 6
        assert result["historicalContextDefaultCount"] == 29
        assert len(result["trainingFingerprint"]) == 64
        assert result["trainingOrigins"]["SIMULATION_GENERATED"] == 24
        assert result["holdoutOrigins"]["SIMULATION_GENERATED"] == 6
        assert [item["modelType"] for item in result["candidates"]] == [
            "RANDOM_FOREST", "LINEAR_REGRESSION"
        ]
        assert all(len(item["sha256"]) == 64 for item in result["candidates"])

        validation_request = {
            "contractVersion": 1,
            "modelVersionId": MODEL,
            "breadCategoryId": CATEGORY,
            "lifecycleStatus": "CANDIDATE",
            "artifactKey": result["candidates"][0]["artifactKey"],
            "artifactSha256": result["candidates"][0]["sha256"],
        }
        valid = client.post(
            "/artifacts/validate", json=validation_request,
            headers={"X-ML-Internal-Token": "test-only-secret"},
        )
        assert valid.status_code == 200
        assert valid.json()["valid"] is True
        validation_request["lifecycleStatus"] = "INACTIVE"
        previous = client.post(
            "/artifacts/validate", json=validation_request,
            headers={"X-ML-Internal-Token": "test-only-secret"},
        )
        assert previous.status_code == 200
        assert previous.json()["valid"] is True
        validation_request["artifactSha256"] = "0" * 64
        invalid = client.post(
            "/artifacts/validate", json=validation_request,
            headers={"X-ML-Internal-Token": "test-only-secret"},
        )
        assert invalid.status_code == 200
        assert invalid.json()["valid"] is False

        request = payload(30)
        request["activeModel"] = {
            "modelVersionId": MODEL,
            "breadCategoryId": CATEGORY,
            "modelType": "RANDOM_FOREST",
            "lifecycleStatus": "ACTIVE",
            "artifactKey": result["candidates"][0]["artifactKey"],
        }
        predicted = client.post(
            "/predict", json=request,
            headers={"X-ML-Internal-Token": "test-only-secret"},
        )
        assert predicted.status_code == 200, predicted.text
        prediction = predicted.json()
        assert prediction["predictionMode"] == "MODEL"
        assert prediction["modelVersionId"] == MODEL
        assert prediction["predictedUnitsSold"] >= 0
        assert 0 <= prediction["confidence"] <= 100
        assert prediction["lowConfidence"] == (prediction["confidence"] < 75)
    finally:
        app.dependency_overrides.clear()


def test_t_dp_api_07_training_rejects_insufficient_or_nonlater_holdout(monkeypatch) -> None:
    """T-DP-API-07: BR-DP-03, FR-DP-01."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    request = {
        "contractVersion": 1,
        "breadCategoryId": CATEGORY,
        "rfModelVersionId": MODEL,
        "lrModelVersionId": "00000000-0000-4000-8000-000000000004",
        "holdoutStart": "2026-10-29",
        "observations": payload(29)["observations"],
    }
    client = TestClient(app)
    headers = {"X-ML-Internal-Token": "test-only-secret"}
    assert client.post("/train", json=request, headers=headers).status_code == 422
    request["observations"] = payload(30)["observations"]
    request["holdoutStart"] = TARGET.isoformat()
    assert client.post("/train", json=request, headers=headers).status_code == 422


def test_t_dp_api_05_requires_internal_token_and_valid_dto(monkeypatch) -> None:
    """T-DP-API-05: NFR-SEC-01, NFR-DAT-01."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    client = TestClient(app)
    for headers in ({}, {"X-ML-Internal-Token": "wrong"}):
        response = client.post("/predict", json=payload(), headers=headers)
        assert response.status_code == 401
        assert response.json()["detail"]["code"] == "ML_UNAUTHORIZED"
    invalid = payload()
    invalid["observations"].append(invalid["observations"][0])
    response = client.post(
        "/predict", json=invalid,
        headers={"X-ML-Internal-Token": "test-only-secret"},
    )
    assert response.status_code == 422


def test_t_dp_api_06_requires_server_configuration(monkeypatch) -> None:
    """T-DP-API-06: NFR-SEC-01."""
    monkeypatch.delenv("ML_INTERNAL_TOKEN", raising=False)
    response = TestClient(app).post("/predict", json=payload())
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "ML_NOT_CONFIGURED"
