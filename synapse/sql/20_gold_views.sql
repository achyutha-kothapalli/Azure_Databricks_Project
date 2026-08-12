USE [$(DatabaseName)];
GO

CREATE OR ALTER VIEW [gold].[dim_date]
AS
SELECT
    source_rows.[Date] AS [date_key],
    source_rows.[Month] AS [month_number],
    source_rows.[Year] AS [year_number],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'calendar',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [Date] date,
    [Month] int,
    [Year] int,
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[dim_customer]
AS
SELECT
    source_rows.[CustomerKey] AS [customer_key],
    source_rows.[FullName] AS [full_name],
    source_rows.[BirthDate] AS [birth_date],
    source_rows.[MaritalStatus] AS [marital_status],
    source_rows.[Gender] AS [gender],
    source_rows.[AnnualIncome] AS [annual_income],
    source_rows.[TotalChildren] AS [total_children],
    source_rows.[EducationLevel] AS [education_level],
    source_rows.[Occupation] AS [occupation],
    source_rows.[HomeOwner] AS [home_owner],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'customers',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [CustomerKey] int,
    [FullName] varchar(200),
    [BirthDate] date,
    [MaritalStatus] varchar(1),
    [Gender] varchar(2),
    [AnnualIncome] decimal(18, 2),
    [TotalChildren] int,
    [EducationLevel] varchar(100),
    [Occupation] varchar(100),
    [HomeOwner] varchar(1),
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[dim_product_category]
AS
SELECT
    source_rows.[ProductCategoryKey] AS [product_category_key],
    source_rows.[CategoryName] AS [category_name],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'product_categories',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [ProductCategoryKey] int,
    [CategoryName] varchar(100),
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[dim_product_subcategory]
AS
SELECT
    source_rows.[ProductSubcategoryKey] AS [product_subcategory_key],
    source_rows.[ProductCategoryKey] AS [product_category_key],
    source_rows.[SubcategoryName] AS [subcategory_name],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'product_subcategories',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [ProductSubcategoryKey] int,
    [ProductCategoryKey] int,
    [SubcategoryName] varchar(100),
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[dim_product]
AS
SELECT
    source_rows.[ProductKey] AS [product_key],
    source_rows.[ProductSubcategoryKey] AS [product_subcategory_key],
    source_rows.[ProductSKU] AS [product_sku],
    source_rows.[ProductName] AS [product_name],
    source_rows.[ModelName] AS [model_name],
    source_rows.[ProductDescription] AS [product_description],
    source_rows.[ProductColor] AS [product_color],
    source_rows.[ProductSize] AS [product_size],
    source_rows.[ProductStyle] AS [product_style],
    source_rows.[ProductCost] AS [product_cost],
    source_rows.[ProductPrice] AS [product_price],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'products',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [ProductKey] int,
    [ProductSubcategoryKey] int,
    [ProductSKU] varchar(50),
    [ProductName] varchar(200),
    [ModelName] varchar(100),
    [ProductDescription] varchar(2000),
    [ProductColor] varchar(50),
    [ProductSize] varchar(50),
    [ProductStyle] varchar(50),
    [ProductCost] decimal(18, 4),
    [ProductPrice] decimal(18, 4),
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[dim_territory]
AS
SELECT
    source_rows.[SalesTerritoryKey] AS [territory_key],
    source_rows.[Region] AS [region],
    source_rows.[Country] AS [country],
    source_rows.[Continent] AS [continent],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'territories',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [SalesTerritoryKey] int,
    [Region] varchar(100),
    [Country] varchar(100),
    [Continent] varchar(100),
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[fact_sales]
AS
SELECT
    source_rows.[OrderDate] AS [order_date],
    source_rows.[StockDate] AS [stock_date],
    source_rows.[OrderNumber] AS [order_number],
    source_rows.[OrderLineItem] AS [order_line_item],
    source_rows.[ProductKey] AS [product_key],
    source_rows.[CustomerKey] AS [customer_key],
    source_rows.[TerritoryKey] AS [territory_key],
    source_rows.[OrderQuantity] AS [order_quantity],
    source_rows.[OrderYear] AS [order_year],
    source_rows.[OrderMonth] AS [order_month],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'sales',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [OrderDate] date,
    [StockDate] date,
    [OrderNumber] varchar(50),
    [ProductKey] int,
    [CustomerKey] int,
    [TerritoryKey] int,
    [OrderLineItem] int,
    [OrderQuantity] int,
    [OrderYear] int,
    [OrderMonth] int,
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO

CREATE OR ALTER VIEW [gold].[fact_returns]
AS
SELECT
    source_rows.[ReturnDate] AS [return_date],
    source_rows.[TerritoryKey] AS [territory_key],
    source_rows.[ProductKey] AS [product_key],
    source_rows.[ReturnQuantity] AS [return_quantity],
    source_rows.[_ingested_at] AS [ingested_at],
    source_rows.[_source_file] AS [source_file],
    source_rows.[_run_id] AS [run_id]
FROM OPENROWSET(
    BULK 'returns',
    DATA_SOURCE = 'SilverDataSource',
    FORMAT = 'DELTA'
)
WITH (
    [ReturnDate] date,
    [TerritoryKey] int,
    [ProductKey] int,
    [ReturnQuantity] int,
    [_ingested_at] datetime2(6),
    [_source_file] varchar(2048),
    [_run_id] varchar(100)
) AS source_rows;
GO
