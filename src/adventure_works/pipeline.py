"""Bronze-to-silver orchestration, quality checks, and idempotent Delta writes."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from adventure_works.quality import (
    assert_accepted_values,
    assert_foreign_keys,
    assert_non_null,
    assert_positive,
    assert_unique,
)
from adventure_works.schemas import BRONZE_SCHEMAS
from adventure_works.transforms import TRANSFORMS

if TYPE_CHECKING:
    from delta.tables import DeltaTable

LoadMode = Literal["upsert", "overwrite"]


@dataclass(frozen=True)
class DatasetSpec:
    """Runtime contract for one bronze source and silver Delta target."""

    source_folders: tuple[str, ...]
    target_name: str
    merge_keys: tuple[str, ...] = ()

    @property
    def is_fact(self) -> bool:
        """Return whether the target uses a Delta merge in normal operation."""
        return bool(self.merge_keys)


DATASETS: dict[str, DatasetSpec] = {
    "calendar": DatasetSpec(("AdventureWorks_Calendar",), "calendar"),
    "customers": DatasetSpec(("AdventureWorks_Customers",), "customers"),
    "product_categories": DatasetSpec(
        ("AdventureWorks_Product_Categories",),
        "product_categories",
    ),
    "product_subcategories": DatasetSpec(
        ("Product_Subcategories",),
        "product_subcategories",
    ),
    "products": DatasetSpec(("AdventureWorks_Products",), "products"),
    "returns": DatasetSpec(
        ("AdventureWorks_Returns",),
        "returns",
        ("ReturnDate", "TerritoryKey", "ProductKey"),
    ),
    "sales": DatasetSpec(
        (
            "AdventureWorks_Sales_2015",
            "AdventureWorks_Sales_2016",
            "AdventureWorks_Sales_2017",
        ),
        "sales",
        ("OrderNumber", "OrderLineItem"),
    ),
    "territories": DatasetSpec(("AdventureWorks_Territories",), "territories"),
}


def layer_root(storage_account: str, layer: str) -> str:
    """Build an ABFSS root without embedding credentials."""
    return f"abfss://{layer}@{storage_account}.dfs.core.windows.net"


def read_bronze_dataset(
    spark: SparkSession,
    bronze_root: str,
    dataset: str,
) -> DataFrame:
    """Read a bronze dataset with its explicit schema and source-file lineage."""
    spec = DATASETS[dataset]
    source_paths = [f"{bronze_root}/{folder}" for folder in spec.source_folders]
    return (
        spark.read.format("csv")
        .option("header", True)
        .option("mode", "FAILFAST")
        .schema(BRONZE_SCHEMAS[dataset])
        .load(source_paths)
        .withColumn("_source_file", F.input_file_name())
    )


def transform_all(
    spark: SparkSession,
    bronze_root: str,
    run_id: str,
) -> dict[str, DataFrame]:
    """Read and transform every source without writing any target."""
    return {
        dataset: TRANSFORMS[dataset](
            read_bronze_dataset(spark, bronze_root, dataset),
            run_id,
            None,
        )
        for dataset in DATASETS
    }


def validate_dataset(dataset: str, df: DataFrame) -> None:
    """Apply dataset-level key, date, category, and measure rules."""
    if dataset == "calendar":
        assert_non_null(df, ["Date"], dataset)
        assert_unique(df, ["Date"], dataset)
    elif dataset == "customers":
        assert_non_null(df, ["CustomerKey", "BirthDate", "FirstName", "LastName"], dataset)
        assert_unique(df, ["CustomerKey"], dataset)
        assert_accepted_values(df, "Gender", {"F", "M", "NA"}, dataset)
        assert_accepted_values(df, "MaritalStatus", {"M", "S"}, dataset)
    elif dataset == "product_categories":
        assert_non_null(df, ["ProductCategoryKey", "CategoryName"], dataset)
        assert_unique(df, ["ProductCategoryKey"], dataset)
    elif dataset == "product_subcategories":
        assert_non_null(
            df,
            ["ProductSubcategoryKey", "ProductCategoryKey", "SubcategoryName"],
            dataset,
        )
        assert_unique(df, ["ProductSubcategoryKey"], dataset)
    elif dataset == "products":
        assert_non_null(
            df,
            ["ProductKey", "ProductSubcategoryKey", "ProductSKU", "ProductName"],
            dataset,
        )
        assert_unique(df, ["ProductKey"], dataset)
    elif dataset == "returns":
        keys = list(DATASETS[dataset].merge_keys)
        assert_non_null(df, [*keys, "ReturnQuantity"], dataset)
        assert_unique(df, keys, dataset)
        assert_positive(df, "ReturnQuantity", dataset)
    elif dataset == "sales":
        keys = list(DATASETS[dataset].merge_keys)
        assert_non_null(
            df,
            [
                *keys,
                "OrderDate",
                "StockDate",
                "ProductKey",
                "CustomerKey",
                "TerritoryKey",
                "OrderQuantity",
            ],
            dataset,
        )
        assert_unique(df, keys, dataset)
        assert_positive(df, "OrderQuantity", dataset)
    elif dataset == "territories":
        assert_non_null(df, ["SalesTerritoryKey", "Region", "Country", "Continent"], dataset)
        assert_unique(df, ["SalesTerritoryKey"], dataset)
    else:
        raise ValueError(f"Unknown dataset: {dataset}")


def validate_relationships(frames: dict[str, DataFrame]) -> None:
    """Enforce relationships needed by downstream analytics."""
    assert_foreign_keys(
        frames["product_subcategories"],
        frames["product_categories"],
        {"ProductCategoryKey": "ProductCategoryKey"},
        "product_subcategories",
        "product_categories",
    )
    assert_foreign_keys(
        frames["products"],
        frames["product_subcategories"],
        {"ProductSubcategoryKey": "ProductSubcategoryKey"},
        "products",
        "product_subcategories",
    )
    for fact in ("sales", "returns"):
        assert_foreign_keys(
            frames[fact],
            frames["products"],
            {"ProductKey": "ProductKey"},
            fact,
            "products",
        )
        assert_foreign_keys(
            frames[fact],
            frames["territories"],
            {"TerritoryKey": "SalesTerritoryKey"},
            fact,
            "territories",
        )
    assert_foreign_keys(
        frames["sales"],
        frames["customers"],
        {"CustomerKey": "CustomerKey"},
        "sales",
        "customers",
    )


def validate_all(frames: dict[str, DataFrame]) -> None:
    """Run all quality checks before the first silver write."""
    if set(frames) != set(DATASETS):
        missing = sorted(set(DATASETS) - set(frames))
        unexpected = sorted(set(frames) - set(DATASETS))
        raise ValueError(f"Dataset collection mismatch; missing={missing}, unexpected={unexpected}")
    for dataset, frame in frames.items():
        validate_dataset(dataset, frame)
    validate_relationships(frames)


def _overwrite_delta(df: DataFrame, target_path: str, run_id: str) -> None:
    """Atomically replace a small target using Delta schema enforcement."""
    (
        df.write.format("delta")
        .mode("overwrite")
        .option("userMetadata", f"run_id={run_id}")
        .save(target_path)
    )


def _merge_delta(
    spark: SparkSession,
    df: DataFrame,
    target_path: str,
    merge_keys: tuple[str, ...],
    run_id: str,
) -> None:
    """Insert or update a fact target using its validated business key."""
    from delta.tables import DeltaTable

    if not DeltaTable.isDeltaTable(spark, target_path):
        _overwrite_delta(df, target_path, run_id)
        return

    condition = " AND ".join(f"target.`{key}` = source.`{key}`" for key in merge_keys)
    target: DeltaTable = DeltaTable.forPath(spark, target_path)
    (
        target.alias("target")
        .merge(df.alias("source"), condition)
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )


def write_silver(
    spark: SparkSession,
    frames: dict[str, DataFrame],
    silver_root: str,
    load_mode: LoadMode,
    run_id: str,
) -> None:
    """Write validated frames using overwrite for dimensions and merge for facts."""
    if load_mode not in ("upsert", "overwrite"):
        raise ValueError(f"Unsupported load mode: {load_mode}")

    for dataset, spec in DATASETS.items():
        target_path = f"{silver_root}/{spec.target_name}"
        if spec.is_fact and load_mode == "upsert":
            _merge_delta(spark, frames[dataset], target_path, spec.merge_keys, run_id)
        else:
            _overwrite_delta(frames[dataset], target_path, run_id)


def run_pipeline(
    spark: SparkSession,
    storage_account: str,
    source_layer: str,
    target_layer: str,
    load_mode: LoadMode,
    run_id: str,
) -> dict[str, int]:
    """Transform, validate, persist, and return silver row counts."""
    bronze_root = layer_root(storage_account, source_layer)
    silver_root = layer_root(storage_account, target_layer)
    frames = transform_all(spark, bronze_root, run_id)
    validate_all(frames)
    write_silver(spark, frames, silver_root, load_mode, run_id)
    return {
        dataset: spark.read.format("delta")
        .load(f"{silver_root}/{spec.target_name}")
        .count()
        for dataset, spec in DATASETS.items()
    }
