"""Shared pytest fixtures for local PySpark unit tests."""

from __future__ import annotations

import os
from collections.abc import Iterator

import pytest


@pytest.fixture(scope="session")
def spark() -> Iterator[object]:
    """Provide one quiet local Spark session for DataFrame unit tests."""
    pyspark = pytest.importorskip("pyspark")
    if not os.environ.get("JAVA_HOME"):
        pytest.skip("JAVA_HOME is required for local PySpark tests")

    session = (
        pyspark.sql.SparkSession.builder.master("local[2]")
        .appName("adventure-works-unit-tests")
        .config("spark.ui.enabled", "false")
        .config("spark.sql.shuffle.partitions", "2")
        .getOrCreate()
    )
    session.sparkContext.setLogLevel("ERROR")
    yield session
    session.stop()
