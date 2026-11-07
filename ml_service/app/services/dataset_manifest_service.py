import json
from hashlib import sha256
from uuid import UUID

from app.schemas.prediction import SelectedObservationDto
from app.services.feature_preparation_service import FEATURE_VERSION


class DatasetManifestService:
    """Make dataset identity depend on dates, targets, origins and feature inputs."""

    @staticmethod
    def observations(items: list[SelectedObservationDto]) -> list[dict]:
        return [
            item.model_dump(mode="json", by_alias=True)
            for item in sorted(items, key=lambda row: row.sales_date)
        ]

    @staticmethod
    def fingerprint(category_id: UUID, items: list[SelectedObservationDto]) -> str:
        return DatasetManifestService.digest({
            "breadCategoryId": str(category_id),
            "featureVersion": FEATURE_VERSION,
            "observations": DatasetManifestService.observations(items),
        })

    @staticmethod
    def digest(manifest: dict) -> str:
        canonical = json.dumps(
            manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        )
        return sha256(canonical.encode("utf-8")).hexdigest()
