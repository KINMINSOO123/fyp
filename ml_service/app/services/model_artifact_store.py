from dataclasses import dataclass
from datetime import date
from hashlib import sha256
from os import link
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Literal
from uuid import UUID

import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.utils.validation import check_is_fitted

from app.services.feature_preparation_service import FEATURE_NAMES, FEATURE_VERSION
from app.services.prediction_mode_service import ActiveModelReference


Estimator = RandomForestRegressor | LinearRegression


@dataclass(frozen=True)
class StoredModel:
    category_id: str
    model_version_id: str
    model_type: Literal["RANDOM_FOREST", "LINEAR_REGRESSION"]
    feature_version: int
    feature_names: tuple[str, ...]
    training_end: date
    holdout_start: date
    training_fingerprint: str
    estimator: Estimator


@dataclass(frozen=True)
class SavedArtifact:
    artifact_key: str
    sha256_hex: str


class ModelArtifactStore:
    """Retain service-created model files below the private artifact directory."""

    def __init__(self, root: Path | None = None) -> None:
        self.root = (root or Path(__file__).resolve().parents[2] / "artifacts").resolve()

    def save_candidate(self, bundle: StoredModel) -> SavedArtifact:
        if not self._valid_bundle(bundle):
            raise ValueError("Candidate artifact is not a fitted supported model.")
        category = UUID(bundle.category_id)
        version = UUID(bundle.model_version_id)
        key = f"models/{category}/{version}.joblib"
        path = self._safe_path(key)
        if path is None:
            raise ValueError("Invalid candidate artifact key.")
        if path.exists():
            raise FileExistsError("A candidate artifact with this identity already exists.")
        path.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(dir=path.parent, suffix=".tmp", delete=False) as temp:
            temp_path = Path(temp.name)
        try:
            joblib.dump(bundle, temp_path)
            # Hard-link creation is atomic and fails if another candidate won the ID.
            link(temp_path, path)
            return SavedArtifact(key, sha256(path.read_bytes()).hexdigest())
        finally:
            temp_path.unlink(missing_ok=True)

    def load_random_forest(self, model: ActiveModelReference) -> StoredModel | None:
        bundle = self.load(model.artifact_key)
        if bundle is None or (
            bundle.model_type != "RANDOM_FOREST"
            or not isinstance(bundle.estimator, RandomForestRegressor)
            or bundle.category_id != model.bread_category_id
            or bundle.model_version_id != model.model_version_id
        ):
            return None
        return bundle

    def is_valid_random_forest(self, model: ActiveModelReference) -> bool:
        return self.load_random_forest(model) is not None

    def verify_random_forest(
        self, model: ActiveModelReference, expected_sha256: str,
    ) -> StoredModel | None:
        path = self._safe_path(model.artifact_key)
        if path is None or not path.is_file():
            return None
        try:
            if sha256(path.read_bytes()).hexdigest() != expected_sha256:
                return None
        except OSError:
            return None
        return self.load_random_forest(model)

    def remove_candidate(self, key: str) -> None:
        path = self._safe_path(key)
        if path is None:
            raise ValueError("Invalid candidate artifact key.")
        path.unlink(missing_ok=True)

    def load(self, key: str) -> StoredModel | None:
        path = self._safe_path(key)
        if path is None or not path.is_file():
            return None
        try:
            bundle = joblib.load(path)
            if not isinstance(bundle, StoredModel):
                return None
            if not self._valid_bundle(bundle):
                return None
        except Exception:
            return None
        return bundle

    @staticmethod
    def _valid_bundle(bundle: StoredModel) -> bool:
        if (
            bundle.feature_version != FEATURE_VERSION
            or bundle.feature_names != FEATURE_NAMES
            or len(bundle.training_fingerprint) != 64
            or any(char not in "0123456789abcdef" for char in bundle.training_fingerprint)
            or bundle.training_end >= bundle.holdout_start
            or (bundle.model_type == "RANDOM_FOREST" and not isinstance(
                bundle.estimator, RandomForestRegressor
            ))
            or (bundle.model_type == "LINEAR_REGRESSION" and not isinstance(
                bundle.estimator, LinearRegression
            ))
            or bundle.model_type not in ("RANDOM_FOREST", "LINEAR_REGRESSION")
        ):
            return False
        try:
            check_is_fitted(bundle.estimator)
        except Exception:
            return False
        return True

    def _safe_path(self, key: str) -> Path | None:
        relative = Path(key)
        if relative.is_absolute() or relative.suffix != ".joblib":
            return None
        path = (self.root / relative).resolve()
        if not path.is_relative_to(self.root):
            return None
        return path
