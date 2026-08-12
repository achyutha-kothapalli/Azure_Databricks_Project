"""Pure DataFrame transformations for the Adventure Works silver layer."""

from __future__ import annotations

from collections.abc import Callable

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

DATE_FORMAT = "M/d/yyyy"


def _with_audit_columns(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Append standard lineage fields without performing any I/O."""
    if not run_id.strip():
        raise ValueError("run_id must not be empty")

    result = df
    if source_file is not None:
        result = result.withColumn("_source_file", F.lit(source_file))
    elif "_source_file" not in result.columns:
        raise ValueError("_source_file must exist when source_file is not supplied")

    return result.withColumn("_ingested_at", F.current_timestamp()).withColumn(
        "_run_id", F.lit(run_id)
    )


def transform_calendar(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Parse calendar dates and derive month and year attributes."""
    return (
        df.withColumn("Date", F.to_date("Date", DATE_FORMAT))
        .withColumn("Month", F.month("Date"))
        .withColumn("Year", F.year("Date"))
        .transform(lambda value: _with_audit_columns(value, run_id, source_file))
    )


def transform_customers(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Parse customer attributes and create a normalized display name."""
    return (
        df.withColumn("BirthDate", F.to_date("BirthDate", DATE_FORMAT))
        .withColumn(
            "AnnualIncome",
            F.regexp_replace(F.col("AnnualIncome"), r"[$,\s]", "").cast(
                DecimalType(18, 2)
            ),
        )
        .withColumn(
            "FullName",
            F.trim(
                F.regexp_replace(
                    F.concat_ws(" ", "Prefix", "FirstName", "LastName"),
                    r"\s+",
                    " ",
                )
            ),
        )
        .transform(lambda value: _with_audit_columns(value, run_id, source_file))
    )


def transform_product_categories(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Preserve product category attributes and add audit columns."""
    return _with_audit_columns(df, run_id, source_file)


def transform_product_subcategories(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Preserve product subcategory attributes and add audit columns."""
    return _with_audit_columns(df, run_id, source_file)


def transform_products(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Preserve complete product names and SKUs and add audit columns."""
    return _with_audit_columns(df, run_id, source_file)


def transform_returns(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Parse return dates and preserve the validated return business key."""
    return df.withColumn("ReturnDate", F.to_date("ReturnDate", DATE_FORMAT)).transform(
        lambda value: _with_audit_columns(value, run_id, source_file)
    )


def transform_sales(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Parse sales dates and derive stable order-date attributes."""
    return (
        df.withColumn("OrderDate", F.to_date("OrderDate", DATE_FORMAT))
        .withColumn("StockDate", F.to_date("StockDate", DATE_FORMAT))
        .withColumn("OrderYear", F.year("OrderDate"))
        .withColumn("OrderMonth", F.month("OrderDate"))
        .transform(lambda value: _with_audit_columns(value, run_id, source_file))
    )


def transform_territories(
    df: DataFrame,
    run_id: str,
    source_file: str | None = None,
) -> DataFrame:
    """Preserve territory attributes and add audit columns."""
    return _with_audit_columns(df, run_id, source_file)


Transform = Callable[[DataFrame, str, str | None], DataFrame]

TRANSFORMS: dict[str, Transform] = {
    "calendar": transform_calendar,
    "customers": transform_customers,
    "product_categories": transform_product_categories,
    "product_subcategories": transform_product_subcategories,
    "products": transform_products,
    "returns": transform_returns,
    "sales": transform_sales,
    "territories": transform_territories,
}
