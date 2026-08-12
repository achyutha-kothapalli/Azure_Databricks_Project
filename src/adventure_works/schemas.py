"""Explicit schemas for Adventure Works bronze CSV datasets."""

from pyspark.sql.types import (
    DecimalType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

CALENDAR_SCHEMA = StructType(
    [
        StructField("Date", StringType(), nullable=False),
    ]
)

CUSTOMERS_SCHEMA = StructType(
    [
        StructField("CustomerKey", IntegerType(), nullable=False),
        StructField("Prefix", StringType(), nullable=True),
        StructField("FirstName", StringType(), nullable=False),
        StructField("LastName", StringType(), nullable=False),
        StructField("BirthDate", StringType(), nullable=False),
        StructField("MaritalStatus", StringType(), nullable=False),
        StructField("Gender", StringType(), nullable=False),
        StructField("EmailAddress", StringType(), nullable=False),
        StructField("AnnualIncome", StringType(), nullable=True),
        StructField("TotalChildren", IntegerType(), nullable=True),
        StructField("EducationLevel", StringType(), nullable=True),
        StructField("Occupation", StringType(), nullable=True),
        StructField("HomeOwner", StringType(), nullable=True),
    ]
)

PRODUCT_CATEGORIES_SCHEMA = StructType(
    [
        StructField("ProductCategoryKey", IntegerType(), nullable=False),
        StructField("CategoryName", StringType(), nullable=False),
    ]
)

PRODUCT_SUBCATEGORIES_SCHEMA = StructType(
    [
        StructField("ProductSubcategoryKey", IntegerType(), nullable=False),
        StructField("SubcategoryName", StringType(), nullable=False),
        StructField("ProductCategoryKey", IntegerType(), nullable=False),
    ]
)

PRODUCTS_SCHEMA = StructType(
    [
        StructField("ProductKey", IntegerType(), nullable=False),
        StructField("ProductSubcategoryKey", IntegerType(), nullable=False),
        StructField("ProductSKU", StringType(), nullable=False),
        StructField("ProductName", StringType(), nullable=False),
        StructField("ModelName", StringType(), nullable=True),
        StructField("ProductDescription", StringType(), nullable=True),
        StructField("ProductColor", StringType(), nullable=True),
        StructField("ProductSize", StringType(), nullable=True),
        StructField("ProductStyle", StringType(), nullable=True),
        StructField("ProductCost", DecimalType(18, 4), nullable=True),
        StructField("ProductPrice", DecimalType(18, 4), nullable=True),
    ]
)

RETURNS_SCHEMA = StructType(
    [
        StructField("ReturnDate", StringType(), nullable=False),
        StructField("TerritoryKey", IntegerType(), nullable=False),
        StructField("ProductKey", IntegerType(), nullable=False),
        StructField("ReturnQuantity", IntegerType(), nullable=False),
    ]
)

SALES_SCHEMA = StructType(
    [
        StructField("OrderDate", StringType(), nullable=False),
        StructField("StockDate", StringType(), nullable=False),
        StructField("OrderNumber", StringType(), nullable=False),
        StructField("ProductKey", IntegerType(), nullable=False),
        StructField("CustomerKey", IntegerType(), nullable=False),
        StructField("TerritoryKey", IntegerType(), nullable=False),
        StructField("OrderLineItem", IntegerType(), nullable=False),
        StructField("OrderQuantity", IntegerType(), nullable=False),
    ]
)

TERRITORIES_SCHEMA = StructType(
    [
        StructField("SalesTerritoryKey", IntegerType(), nullable=False),
        StructField("Region", StringType(), nullable=False),
        StructField("Country", StringType(), nullable=False),
        StructField("Continent", StringType(), nullable=False),
    ]
)

BRONZE_SCHEMAS: dict[str, StructType] = {
    "calendar": CALENDAR_SCHEMA,
    "customers": CUSTOMERS_SCHEMA,
    "product_categories": PRODUCT_CATEGORIES_SCHEMA,
    "product_subcategories": PRODUCT_SUBCATEGORIES_SCHEMA,
    "products": PRODUCTS_SCHEMA,
    "returns": RETURNS_SCHEMA,
    "sales": SALES_SCHEMA,
    "territories": TERRITORIES_SCHEMA,
}
