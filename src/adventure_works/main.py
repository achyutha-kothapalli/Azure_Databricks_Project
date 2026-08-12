"""Databricks entry point for the Adventure Works bronze-to-silver pipeline."""

from __future__ import annotations

import argparse
import json
import re
import uuid
from collections.abc import Sequence

from pyspark.sql import SparkSession

from adventure_works.pipeline import run_pipeline

STORAGE_ACCOUNT_PATTERN = re.compile(r"^[a-z0-9]{3,24}$")
LAYER_PATTERN = re.compile(r"^[a-z][a-z0-9-]{1,31}$")


def build_parser() -> argparse.ArgumentParser:
    """Define the stable command-line interface used by Databricks jobs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("dev", "test", "prod"), required=True)
    parser.add_argument("--storage-account", required=True)
    parser.add_argument("--source-layer", default="bronze")
    parser.add_argument("--target-layer", default="silver")
    parser.add_argument("--load-mode", choices=("upsert", "overwrite"), default="upsert")
    parser.add_argument("--run-id", default=None)
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse and validate runtime values before starting Spark work."""
    args = build_parser().parse_args(argv)
    if not STORAGE_ACCOUNT_PATTERN.fullmatch(args.storage_account):
        raise ValueError("storage account must contain 3-24 lowercase letters or digits")
    for argument in ("source_layer", "target_layer"):
        value = getattr(args, argument)
        if not LAYER_PATTERN.fullmatch(value):
            raise ValueError(f"{argument.replace('_', ' ')} has an invalid name: {value}")
    if args.source_layer == args.target_layer:
        raise ValueError("source layer and target layer must be different")
    if args.run_id is not None and not args.run_id.strip():
        raise ValueError("run ID must not be empty")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    """Execute the validated pipeline and emit a machine-readable summary."""
    args = parse_args(argv)
    run_id = args.run_id or str(uuid.uuid4())
    spark = SparkSession.builder.appName(
        f"adventure-works-silver-{args.environment}"
    ).getOrCreate()

    row_counts = run_pipeline(
        spark=spark,
        storage_account=args.storage_account,
        source_layer=args.source_layer,
        target_layer=args.target_layer,
        load_mode=args.load_mode,
        run_id=run_id,
    )
    print(
        json.dumps(
            {
                "environment": args.environment,
                "load_mode": args.load_mode,
                "run_id": run_id,
                "silver_row_counts": row_counts,
                "status": "succeeded",
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
