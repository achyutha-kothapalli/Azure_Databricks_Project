"""Unit tests for pure Adventure Works PySpark transformations and quality rules."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

pytest.importorskip("pyspark")

from adventure_works.pipeline import (
    DATASETS,
    validate_dataset,
    validate_relationships,
    validate_synapse_delta_protocol,
)
from adventure_works.quality import DataQualityError
from adventure_works.schemas import PRODUCTS_SCHEMA, SALES_SCHEMA
from adventure_works.transforms import (
    transform_calendar,
    transform_customers,
    transform_products,
    transform_sales,
)


def test_calendar_parses_date_and_derives_month_and_year(spark: object) -> None:
    """Calendar uses the source's M/d/yyyy format and creates expected attributes."""
    source = spark.createDataFrame([("12/31/2017",)], ["Date"])

    row = transform_calendar(source, "run-calendar", "calendar.csv").first()

    assert row.Date == date(2017, 12, 31)
    assert row.Month == 12
    assert row.Year == 2017
    assert row._source_file == "calendar.csv"
    assert row._run_id == "run-calendar"
    assert row._ingested_at is not None


def test_customer_full_name_income_and_categories(spark: object) -> None:
    """Customer fields are parsed without relying on accidental column casing."""
    source = spark.createDataFrame(
        [(11000, "MR.", "JON", "YANG", "4/8/1966", "M", "M", "$90,000 ")],
        [
            "CustomerKey",
            "Prefix",
            "FirstName",
            "LastName",
            "BirthDate",
            "MaritalStatus",
            "Gender",
            "AnnualIncome",
        ],
    )

    transformed = transform_customers(source, "run-customer", "customers.csv")
    row = transformed.first()

    assert row.FullName == "MR. JON YANG"
    assert row.BirthDate == date(1966, 4, 8)
    assert row.AnnualIncome == Decimal("90000.00")
    validate_dataset("customers", transformed)


def test_products_preserve_complete_name_and_sku(spark: object) -> None:
    """Production transforms must not repeat the notebook's destructive string splitting."""
    source = spark.createDataFrame(
        [
            (
                214,
                31,
                "HL-U509-R",
                "Sport-100 Helmet, Red",
                "Sport-100",
                "Universal fit",
                "Red",
                "0",
                "0",
                Decimal("13.0863"),
                Decimal("34.9900"),
            )
        ],
        PRODUCTS_SCHEMA,
    )

    row = transform_products(source, "run-product", "products.csv").first()

    assert row.ProductSKU == "HL-U509-R"
    assert row.ProductName == "Sport-100 Helmet, Red"


def test_sales_dates_order_number_and_audit_columns(spark: object) -> None:
    """Sales derives date attributes without rewriting its business key."""
    source = spark.createDataFrame(
        [("1/1/2017", "12/13/2003", "SO61285", 529, 23791, 1, 2, 2)],
        SALES_SCHEMA,
    )

    transformed = transform_sales(source, "run-sales", "sales_2017.csv")
    row = transformed.first()

    assert row.OrderDate == date(2017, 1, 1)
    assert row.StockDate == date(2003, 12, 13)
    assert row.OrderNumber == "SO61285"
    assert row.OrderYear == 2017
    assert row.OrderMonth == 1
    assert row._source_file == "sales_2017.csv"
    validate_dataset("sales", transformed)


def test_duplicate_sales_merge_key_fails_quality_rule(spark: object) -> None:
    """A duplicate OrderNumber and OrderLineItem pair must stop the load."""
    rows = [
        ("1/1/2017", "12/13/2003", "SO61285", 529, 23791, 1, 2, 2),
        ("1/1/2017", "12/13/2003", "SO61285", 214, 23791, 1, 2, 1),
    ]
    transformed = transform_sales(
        spark.createDataFrame(rows, SALES_SCHEMA),
        "run-duplicate",
        "sales.csv",
    )

    with pytest.raises(DataQualityError, match="duplicate key"):
        validate_dataset("sales", transformed)


def test_non_positive_sales_quantity_fails_quality_rule(spark: object) -> None:
    """The pipeline must fail clearly when a required positive measure is invalid."""
    source = spark.createDataFrame(
        [("1/1/2017", "12/13/2003", "SO61285", 529, 23791, 1, 2, 0)],
        SALES_SCHEMA,
    )
    transformed = transform_sales(source, "run-invalid", "sales.csv")

    with pytest.raises(DataQualityError, match="positive value"):
        validate_dataset("sales", transformed)


def test_unresolved_sales_customer_fails_relationship_rule(spark: object) -> None:
    """Sales customer keys must resolve to the customer dimension."""
    frames = {
        "sales": spark.createDataFrame(
            [(999, 1, 1)],
            ["CustomerKey", "ProductKey", "TerritoryKey"],
        ),
        "returns": spark.createDataFrame([(1, 1)], ["ProductKey", "TerritoryKey"]),
        "customers": spark.createDataFrame([(11000,)], ["CustomerKey"]),
        "products": spark.createDataFrame([(1, 1)], ["ProductKey", "ProductSubcategoryKey"]),
        "territories": spark.createDataFrame([(1,)], ["SalesTerritoryKey"]),
        "product_subcategories": spark.createDataFrame(
            [(1, 1)], ["ProductSubcategoryKey", "ProductCategoryKey"]
        ),
        "product_categories": spark.createDataFrame([(1,)], ["ProductCategoryKey"]),
    }

    with pytest.raises(DataQualityError, match="unresolved key"):
        validate_relationships(frames)


def test_synapse_delta_protocol_rejects_unsupported_features() -> None:
    """Serving compatibility fails before unsupported Delta features are written again."""
    validate_synapse_delta_protocol(1, 2, {"delta.checkpointPolicy": "classic"})

    with pytest.raises(ValueError, match="deletion vectors"):
        validate_synapse_delta_protocol(
            1,
            7,
            {"delta.enableDeletionVectors": "true"},
        )


def test_fact_merge_keys_are_explicit() -> None:
    """Idempotent facts use the validated source business keys."""
    assert DATASETS["sales"].merge_keys == ("OrderNumber", "OrderLineItem")
    assert DATASETS["returns"].merge_keys == (
        "ReturnDate",
        "TerritoryKey",
        "ProductKey",
    )
