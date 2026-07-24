"""Tests for repository metadata and source-data contracts."""

from tools.validate_repository import validate


def test_repository_contract() -> None:
    """Checked-in datasets and ingestion metadata must remain consistent."""
    assert validate() == []

