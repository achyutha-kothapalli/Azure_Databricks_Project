USE [$(DatabaseName)];
GO

IF (
    SELECT COUNT(*)
    FROM sys.views AS views
    INNER JOIN sys.schemas AS schemas
        ON views.[schema_id] = schemas.[schema_id]
    WHERE schemas.[name] = N'gold'
) <> 10
BEGIN
    THROW 51000, 'Expected ten gold views.', 1;
END;
GO

IF (SELECT COUNT_BIG(*) FROM [gold].[dim_date]) <> 912
    THROW 51000, 'Unexpected dim_date row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[dim_customer]) <> 18148
    THROW 51000, 'Unexpected dim_customer row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[dim_product_category]) <> 4
    THROW 51000, 'Unexpected dim_product_category row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[dim_product_subcategory]) <> 37
    THROW 51000, 'Unexpected dim_product_subcategory row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[dim_product]) <> 293
    THROW 51000, 'Unexpected dim_product row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[dim_territory]) <> 10
    THROW 51000, 'Unexpected dim_territory row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[fact_sales]) <> 56046
    THROW 51000, 'Unexpected fact_sales row count.', 1;
IF (SELECT COUNT_BIG(*) FROM [gold].[fact_returns]) <> 1809
    THROW 51000, 'Unexpected fact_returns row count.', 1;
GO

IF EXISTS (
    SELECT [order_number], [order_line_item]
    FROM [gold].[fact_sales]
    GROUP BY [order_number], [order_line_item]
    HAVING COUNT_BIG(*) > 1
)
    THROW 51000, 'Duplicate fact_sales business keys found.', 1;

IF EXISTS (
    SELECT [return_date], [territory_key], [product_key]
    FROM [gold].[fact_returns]
    GROUP BY [return_date], [territory_key], [product_key]
    HAVING COUNT_BIG(*) > 1
)
    THROW 51000, 'Duplicate fact_returns business keys found.', 1;
GO

SELECT N'dim_date' AS [object_name], COUNT_BIG(*) AS [row_count]
FROM [gold].[dim_date]
UNION ALL
SELECT N'dim_customer', COUNT_BIG(*) FROM [gold].[dim_customer]
UNION ALL
SELECT N'dim_product_category', COUNT_BIG(*) FROM [gold].[dim_product_category]
UNION ALL
SELECT N'dim_product_subcategory', COUNT_BIG(*) FROM [gold].[dim_product_subcategory]
UNION ALL
SELECT N'dim_product', COUNT_BIG(*) FROM [gold].[dim_product]
UNION ALL
SELECT N'dim_territory', COUNT_BIG(*) FROM [gold].[dim_territory]
UNION ALL
SELECT N'fact_sales', COUNT_BIG(*) FROM [gold].[fact_sales]
UNION ALL
SELECT N'fact_returns', COUNT_BIG(*) FROM [gold].[fact_returns];
GO
