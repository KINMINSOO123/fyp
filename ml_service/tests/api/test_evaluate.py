from datetime import date, timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from app.api.routes.predict import get_evaluation_service, get_training_service
from app.main import app
from app.services.model_artifact_store import ModelArtifactStore
from app.services.model_evaluation_service import ModelEvaluationService
from app.services.model_training_service import ModelTrainingService


CATEGORY = "00000000-0000-4000-8000-000000000001"
RF = "00000000-0000-4000-8000-000000000002"
LR = "00000000-0000-4000-8000-000000000003"
TARGET = date(2026, 11, 4)
HEADERS = {"X-ML-Internal-Token": "test-only-secret"}


def observations(count: int = 30) -> list[dict]:
    result = []
    for index in range(count):
        origin = "ACTUAL_TRANSACTION" if index < 20 else "SIMULATION_GENERATED"
        result.append({
            "id": str(UUID(int=100 + index)),
            "breadCategoryId": CATEGORY,
            "salesDate": (TARGET - timedelta(days=count - index)).isoformat(),
            "unitsSold": 0 if index >= 24 else 10 + index,
            "dataOrigin": origin,
            "sourceDailyResultId": str(UUID(int=500 + index))
                if origin == "SIMULATION_GENERATED" else None,
            "externalSourceReference": f"receipt-{index}"
                if origin == "ACTUAL_TRANSACTION" else None,
        })
    return result


def training_request(rows: list[dict]) -> dict:
    return {
        "contractVersion": 1,
        "breadCategoryId": CATEGORY,
        "rfModelVersionId": RF,
        "lrModelVersionId": LR,
        "holdoutStart": "2026-10-29",
        "observations": rows,
    }


def evaluation_request(rows: list[dict], candidates: list[dict]) -> dict:
    return {
        "contractVersion": 1,
        "breadCategoryId": CATEGORY,
        "holdoutStart": "2026-10-29",
        "observations": rows,
        "models": [
            {"role": "CANDIDATE_RF", "modelVersionId": RF,
             "modelType": "RANDOM_FOREST", "artifactKey": candidates[0]["artifactKey"]},
            {"role": "BASELINE_LR", "modelVersionId": LR,
             "modelType": "LINEAR_REGRESSION", "artifactKey": candidates[1]["artifactKey"]},
        ],
    }


def test_t_dp_eval_04_same_later_holdout_and_simulation_label(monkeypatch, tmp_path) -> None:
    """T-DP-EVAL-04: FR-DP-06, BR-DP-04, NFR-ACC-05."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    store = ModelArtifactStore(tmp_path)
    app.dependency_overrides[get_training_service] = lambda: ModelTrainingService(store)
    app.dependency_overrides[get_evaluation_service] = lambda: ModelEvaluationService(store)
    try:
        client = TestClient(app)
        rows = observations()
        trained = client.post("/train", json=training_request(rows), headers=HEADERS)
        assert trained.status_code == 200, trained.text
        request = evaluation_request(rows, trained.json()["candidates"])
        response = client.post("/evaluate", json=request, headers=HEADERS)
        assert response.status_code == 200, response.text
        result = response.json()
        assert result["holdoutStart"] == "2026-10-29"
        assert result["holdoutEnd"] == "2026-11-03"
        assert result["dataOrigins"] == ["SIMULATION_GENERATED"]
        assert result["evaluationLabel"] == "SIMULATION_BASED"
        assert result["originCounts"]["SIMULATION_GENERATED"] == 6
        assert len(result["holdoutFingerprint"]) == 64
        assert len(result["results"]) == 2
        assert {item["sampleCount"] for item in result["results"]} == {6}
        assert {item["mapeSampleCount"] for item in result["results"]} == {0}
        assert all(item["mape"] is None for item in result["results"])
        assert all(item["rSquared"] is None for item in result["results"])
        assert all(item["mae"] >= 0 for item in result["results"])
        assert all(len(item["predictions"]) == 6 for item in result["results"])

        # A changed test actual changes dataset identity; equal dates are insufficient.
        changed = evaluation_request(rows, trained.json()["candidates"])
        changed["observations"] = [dict(item) for item in rows]
        changed["observations"][-1]["unitsSold"] = 1
        changed_result = client.post("/evaluate", json=changed, headers=HEADERS)
        assert changed_result.status_code == 200
        assert changed_result.json()["holdoutFingerprint"] != result["holdoutFingerprint"]

        # Changing fitting history is rejected against the candidate artifact.
        changed["observations"][0]["unitsSold"] = 999
        mismatch = client.post("/evaluate", json=changed, headers=HEADERS)
        assert mismatch.status_code == 422
        assert mismatch.json()["detail"]["code"] == "INVALID_EVALUATION_INPUT"

        # The incumbent is compared on the exact same holdout request.
        incumbent_training = training_request(rows)
        incumbent_training["rfModelVersionId"] = "00000000-0000-4000-8000-000000000005"
        incumbent_training["lrModelVersionId"] = "00000000-0000-4000-8000-000000000006"
        incumbent = client.post("/train", json=incumbent_training, headers=HEADERS)
        assert incumbent.status_code == 200
        with_incumbent = evaluation_request(rows, trained.json()["candidates"])
        with_incumbent["models"].append({
            "role": "CURRENT_ACTIVE_RF",
            "modelVersionId": incumbent_training["rfModelVersionId"],
            "modelType": "RANDOM_FOREST",
            "artifactKey": incumbent.json()["candidates"][0]["artifactKey"],
        })
        compared = client.post("/evaluate", json=with_incumbent, headers=HEADERS)
        assert compared.status_code == 200, compared.text
        assert len(compared.json()["results"]) == 3
        assert compared.json()["holdoutFingerprint"] == result["holdoutFingerprint"]

        # A model fitted using part of this test period is not a valid comparator.
        leaked_training = training_request(rows)
        leaked_training["rfModelVersionId"] = "00000000-0000-4000-8000-000000000007"
        leaked_training["lrModelVersionId"] = "00000000-0000-4000-8000-000000000008"
        leaked_training["holdoutStart"] = "2026-11-01"
        leaked = client.post("/train", json=leaked_training, headers=HEADERS)
        assert leaked.status_code == 200
        with_incumbent["models"][-1]["modelVersionId"] = leaked_training["rfModelVersionId"]
        with_incumbent["models"][-1]["artifactKey"] = leaked.json()["candidates"][0]["artifactKey"]
        rejected = client.post("/evaluate", json=with_incumbent, headers=HEADERS)
        assert rejected.status_code == 422
    finally:
        app.dependency_overrides.clear()


def test_t_dp_eval_05_rejects_nonlater_holdout_and_requires_token(monkeypatch) -> None:
    """T-DP-EVAL-05: BR-DP-02, NFR-SEC-01."""
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-only-secret")
    request = evaluation_request(observations(), [
        {"artifactKey": "models/rf.joblib"}, {"artifactKey": "models/lr.joblib"},
    ])
    client = TestClient(app)
    assert client.post("/evaluate", json=request).status_code == 401
    request["holdoutStart"] = TARGET.isoformat()
    assert client.post("/evaluate", json=request, headers=HEADERS).status_code == 422
