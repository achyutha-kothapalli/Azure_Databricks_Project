"""Run dependency-free checks against source data and ingestion metadata."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "Adventure_Works_Dataset"
CANONICAL_METADATA = ROOT / "config" / "datasets.json"

EXPECTED_ROW_COUNTS = {
    "AdventureWorks_Calendar.csv": 912,
    "AdventureWorks_Customers.csv": 18_148,
    "AdventureWorks_Product_Categories.csv": 4,
    "AdventureWorks_Product_Subcategories.csv": 37,
    "AdventureWorks_Products.csv": 293,
    "AdventureWorks_Returns.csv": 1_809,
    "AdventureWorks_Sales_2015.csv": 2_630,
    "AdventureWorks_Sales_2016.csv": 23_935,
    "AdventureWorks_Sales_2017.csv": 29_481,
    "AdventureWorks_Territories.csv": 10,
}
REQUIRED_FIELDS = {
    "dataset_name",
    "source_path",
    "sink_folder",
    "sink_file",
    "expected_rows",
}


def load_metadata(path: Path) -> list[dict[str, Any]]:
    """Load and minimally type-check a metadata JSON file."""
    with path.open(encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, list):
        raise ValueError(f"{path.relative_to(ROOT)} must contain a JSON array")
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise ValueError(f"Metadata entry {index} must be a JSON object")
        missing = REQUIRED_FIELDS - item.keys()
        if missing:
            raise ValueError(f"Metadata entry {index} is missing: {sorted(missing)}")
    return value


def count_csv_rows(path: Path) -> int:
    """Count CSV records using the source files' supported text encodings."""
    for encoding in ("utf-8-sig", "windows-1252"):
        try:
            with path.open(encoding=encoding, newline="") as file:
                return sum(1 for _ in csv.DictReader(file))
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError("unknown", b"", 0, 1, f"Cannot decode {path.name}")


def validate() -> list[str]:
    """Return validation errors; an empty list means validation passed."""
    errors: list[str] = []
    try:
        canonical = load_metadata(CANONICAL_METADATA)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        return [str(error)]

    if len(canonical) != len(EXPECTED_ROW_COUNTS):
        errors.append(f"Expected 10 metadata entries, found {len(canonical)}")

    dataset_names = [str(item["dataset_name"]) for item in canonical]
    sink_files = [str(item["sink_file"]) for item in canonical]
    sink_folders = [str(item["sink_folder"]) for item in canonical]
    if len(dataset_names) != len(set(dataset_names)):
        errors.append("Metadata contains duplicate dataset names")
    if len(sink_files) != len(set(sink_files)):
        errors.append("Metadata contains duplicate sink filenames")
    if len(sink_folders) != len(set(sink_folders)):
        errors.append("Metadata contains duplicate sink folders")

    for item in canonical:
        dataset_name = str(item["dataset_name"])
        source_name = Path(str(item["source_path"])).name
        sink_name = str(item["sink_file"])
        expected_rows = item["expected_rows"]
        if not dataset_name.replace("_", "").isalnum() or dataset_name.lower() != dataset_name:
            errors.append(f"Dataset name must be lowercase snake case: {dataset_name}")
        if not source_name.lower().endswith(".csv"):
            errors.append(f"Source is not a CSV file: {source_name}")
        if not sink_name.lower().endswith(".csv"):
            errors.append(f"Sink is not a CSV file: {sink_name}")
        if source_name != sink_name:
            errors.append(f"Source/sink filename mismatch: {source_name} != {sink_name}")
        if source_name not in EXPECTED_ROW_COUNTS:
            errors.append(f"Unexpected metadata source file: {source_name}")
        elif expected_rows != EXPECTED_ROW_COUNTS[source_name]:
            errors.append(
                f"{source_name}: metadata expects {expected_rows!r} rows; "
                f"repository contract expects {EXPECTED_ROW_COUNTS[source_name]:,}"
            )

    actual_files = {path.name for path in DATA_DIR.glob("*.csv")}
    expected_files = set(EXPECTED_ROW_COUNTS)
    for name in sorted(expected_files - actual_files):
        errors.append(f"Missing source dataset: {name}")
    for name in sorted(actual_files - expected_files):
        errors.append(f"Unexpected source dataset: {name}")

    for name, expected_count in EXPECTED_ROW_COUNTS.items():
        path = DATA_DIR / name
        if path.exists():
            actual_count = count_csv_rows(path)
            if actual_count != expected_count:
                errors.append(f"{name}: expected {expected_count:,} rows, found {actual_count:,}")
    return errors


def main() -> int:
    """Execute validation and return a shell-friendly exit code."""
    errors = validate()
    if errors:
        print("Repository validation FAILED:")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("Repository validation PASSED")
    print("  Metadata entries: 10")
    print("  CSV datasets: 10")
    print(f"  Total data rows: {sum(EXPECTED_ROW_COUNTS.values()):,}")
    print("  Canonical ingestion metadata matches the source-data contract")
    return 0


if __name__ == "__main__":
    sys.exit(main())
