"""Contracts for metadata-driven Azure Data Factory ingestion."""

from __future__ import annotations

import json
import re
from pathlib import Path

from tools.validate_repository import EXPECTED_ROW_COUNTS

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "datasets.json"
ADF_TERRAFORM = ROOT / "infra" / "platform" / "adf-ingestion.tf"
ENVIRONMENTS = ("dev", "test", "prod")


def read(relative_path: str) -> str:
    """Read a repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_manifest_is_complete_and_deterministic() -> None:
    """The canonical manifest must describe every checked-in source exactly once."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    assert len(manifest) == 10
    assert len({item["dataset_name"] for item in manifest}) == 10
    assert len({item["source_path"] for item in manifest}) == 10
    assert len({item["sink_file"] for item in manifest}) == 10

    actual = {
        Path(item["source_path"]).name: item["expected_rows"] for item in manifest
    }
    assert actual == EXPECTED_ROW_COUNTS


def test_manifest_uses_valid_csv_names() -> None:
    """Source and sink files must retain the expected CSV extension and name."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    for item in manifest:
        source_name = Path(item["source_path"]).name
        assert source_name == item["sink_file"]
        assert item["sink_file"].endswith(".csv")

    sales_2016 = next(item for item in manifest if item["dataset_name"] == "sales_2016")
    assert sales_2016["sink_file"] == "AdventureWorks_Sales_2016.csv"


def test_source_revision_is_commit_pinned() -> None:
    """Every environment must use a raw GitHub URL pinned to a full commit SHA."""
    pattern = re.compile(
        r'^adf_source_base_url\s*=\s*"'
        r"https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/"
        r'"$',
        re.MULTILINE,
    )
    urls: set[str] = set()

    for environment in ENVIRONMENTS:
        values = read(f"infra/environments/{environment}.tfvars.example")
        match = pattern.search(values)
        assert match is not None
        urls.add(match.group(0).split('"', 1)[1].rstrip('"'))

    assert len(urls) == 1


def test_adf_pipeline_is_metadata_driven_and_identity_based() -> None:
    """The pipeline must use Lookup, ForEach, Copy, and managed-identity storage access."""
    terraform = ADF_TERRAFORM.read_text(encoding="utf-8")

    required = (
        'authentication_type = "Anonymous"',
        "use_managed_identity = true",
        'name = "LookupDatasetManifest"',
        'name = "ForEachDataset"',
        'name = "CopyDatasetToBronze"',
        'name = "ValidateBronzeFile"',
        'name = "EnsureBronzeFileExists"',
        'name = "FailMissingBronzeFile"',
        "@activity('LookupDatasetManifest').output.value",
        "@item().source_path",
        "@item().sink_folder",
        "@item().sink_file",
        'fieldList = ["exists", "size"]',
        "@equals(activity('ValidateBronzeFile').output.exists, true)",
        'errorCode = "BRONZE_FILE_MISSING"',
    )
    for value in required:
        assert value in terraform

    forbidden = re.compile(r"(?i)(account_key|sas_token|client_secret|password\s*=)")
    assert forbidden.search(terraform) is None


def test_copy_failure_propagates_to_pipeline() -> None:
    """Child activities must depend on success rather than suppressing copy failures."""
    terraform = ADF_TERRAFORM.read_text(encoding="utf-8")

    assert 'dependencyConditions = ["Succeeded"]' in terraform
    assert 'dependencyConditions = ["Completed"]' not in terraform
    assert "continueOnError" not in terraform


def test_run_verifier_checks_iterations_files_and_rows() -> None:
    """Azure verification must cover the run, child activities, files, and row counts."""
    verifier = read("tools/Invoke-AdfIngestion.ps1")

    required = (
        "pipeline create-run",
        "pipeline-run show",
        "activity-run query-by-pipeline-run",
        "Expected 10 copy activity runs",
        "Expected 10 bronze file checks",
        "Copied row counts do not match the manifest",
        "A bronze file metadata check reported that its file does not exist",
        "adf-ingestion-run.json",
    )
    for value in required:
        assert value in verifier
