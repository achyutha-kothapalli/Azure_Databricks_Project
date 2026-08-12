"""Fail-fast data-quality rules for transformed Adventure Works datasets."""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence

from pyspark.sql import DataFrame
from pyspark.sql import functions as F


class DataQualityError(RuntimeError):
    """Raised when a transformed dataset violates a required contract."""


def require_columns(df: DataFrame, columns: Iterable[str], dataset: str) -> None:
    """Require a DataFrame to contain the named columns."""
    missing = sorted(set(columns) - set(df.columns))
    if missing:
        raise DataQualityError(f"{dataset}: missing required columns: {missing}")


def assert_non_null(df: DataFrame, columns: Sequence[str], dataset: str) -> None:
    """Fail when any required column contains a null value."""
    require_columns(df, columns, dataset)
    null_condition = F.lit(False)
    for column in columns:
        null_condition = null_condition | F.col(column).isNull()
    if df.where(null_condition).limit(1).count():
        raise DataQualityError(f"{dataset}: null value found in required columns {list(columns)}")


def assert_unique(df: DataFrame, columns: Sequence[str], dataset: str) -> None:
    """Fail when a business or dimension key is duplicated."""
    require_columns(df, columns, dataset)
    duplicate_exists = (
        df.groupBy(*columns).count().where(F.col("count") > 1).limit(1).count()
    )
    if duplicate_exists:
        raise DataQualityError(f"{dataset}: duplicate key found for columns {list(columns)}")


def assert_positive(df: DataFrame, column: str, dataset: str) -> None:
    """Require a numeric measure to be strictly positive and non-null."""
    require_columns(df, [column], dataset)
    if df.where(F.col(column).isNull() | (F.col(column) <= 0)).limit(1).count():
        raise DataQualityError(f"{dataset}: {column} must be a positive value")


def assert_accepted_values(
    df: DataFrame,
    column: str,
    accepted_values: Iterable[str],
    dataset: str,
) -> None:
    """Require categorical values to match an explicit documented set."""
    require_columns(df, [column], dataset)
    accepted = sorted(set(accepted_values))
    if df.where(F.col(column).isNull() | ~F.col(column).isin(accepted)).limit(1).count():
        raise DataQualityError(
            f"{dataset}: {column} contains values outside the accepted set {accepted}"
        )


def assert_foreign_keys(
    fact_df: DataFrame,
    dimension_df: DataFrame,
    key_mapping: Mapping[str, str],
    dataset: str,
    dimension: str,
) -> None:
    """Require every fact key to resolve to a dimension key."""
    fact_keys = list(key_mapping)
    dimension_keys = list(key_mapping.values())
    require_columns(fact_df, fact_keys, dataset)
    require_columns(dimension_df, dimension_keys, dimension)

    fact_projection = fact_df.select(*fact_keys).dropDuplicates()
    dimension_projection = dimension_df.select(
        *[F.col(value).alias(key) for key, value in key_mapping.items()]
    ).dropDuplicates()
    missing_exists = fact_projection.join(
        dimension_projection,
        on=fact_keys,
        how="left_anti",
    ).limit(1).count()
    if missing_exists:
        raise DataQualityError(f"{dataset}: unresolved key found for dimension {dimension}")
