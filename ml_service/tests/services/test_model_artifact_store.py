from datetime import date
from pathlib import Path

import pytest
from sklearn.ensemble import RandomForestRegressor

from app.services.feature_preparation_service import FEATURE_NAMES, FEATURE_VERSION
from app.services.model_artifact_store import ModelArtifactStore, StoredModel
from app.services.prediction_mode_service import ActiveModelReference


MODEL_ID = "00000000-0000-4000-8000-000000000002"
CATEGORY_ID = "00000000-0000-4000-8000-000000000001"


def model(key: str) -> ActiveModelReference:
    return ActiveModelReference(
        model_version_id=MODEL_ID,
        bread_category_id=CATEGORY_ID,
        model_type="RANDOM_FOREST",
        lifecycle_status="ACTIVE",
        artifact_key=key,
    )


def test_t_dp_artifact_01_accepts_only_fitted_rf_inside_artifact_root(tmp_path: Path) -> None:
    """T-DP-ART-01: BR-DP-03, FR-DP-06."""
    store = ModelArtifactStore(tmp_path)
    fitted = RandomForestRegressor(n_estimators=2, random_state=0)
    fitted.fit([[0], [1]], [0, 1])
    candidate = StoredModel(
        category_id=CATEGORY_ID, model_version_id=MODEL_ID,
        model_type="RANDOM_FOREST", feature_version=FEATURE_VERSION,
        feature_names=FEATURE_NAMES, training_end=date(2026, 10, 31),
        holdout_start=date(2026, 11, 1),
        training_fingerprint="a" * 64, estimator=fitted,
    )
    saved = store.save_candidate(candidate)
    assert len(saved.sha256_hex) == 64
    assert store.is_valid_random_forest(model(saved.artifact_key))
    assert store.verify_random_forest(model(saved.artifact_key), saved.sha256_hex) is not None
    assert store.verify_random_forest(model(saved.artifact_key), "0" * 64) is None
    assert not store.is_valid_random_forest(model("missing.joblib"))
    assert not store.is_valid_random_forest(model("../outside.joblib"))
    assert not store.is_valid_random_forest(ActiveModelReference(
        "another-model", CATEGORY_ID, "RANDOM_FOREST", "ACTIVE", saved.artifact_key,
    ))
    with pytest.raises(ValueError, match="fitted"):
        store.save_candidate(StoredModel(
            category_id=CATEGORY_ID, model_version_id=MODEL_ID,
            model_type="RANDOM_FOREST", feature_version=FEATURE_VERSION,
            feature_names=FEATURE_NAMES, training_end=date(2026, 10, 31),
            holdout_start=date(2026, 11, 1),
            training_fingerprint="a" * 64,
            estimator=RandomForestRegressor(n_estimators=2),
        ))
