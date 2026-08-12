USE [$(DatabaseName)];
GO

CREATE OR ALTER VIEW [gold].[sales_detail]
AS
SELECT
    sales.[order_date],
    sales.[order_number],
    sales.[order_line_item],
    sales.[order_quantity],
    customer.[customer_key],
    customer.[full_name] AS [customer_name],
    product.[product_key],
    product.[product_sku],
    product.[product_name],
    subcategory.[subcategory_name],
    category.[category_name],
    territory.[region],
    territory.[country],
    territory.[continent],
    product.[product_price],
    CAST(sales.[order_quantity] * product.[product_price] AS decimal(18, 2)) AS [sales_amount],
    sales.[run_id]
FROM [gold].[fact_sales] AS sales
INNER JOIN [gold].[dim_customer] AS customer
    ON sales.[customer_key] = customer.[customer_key]
INNER JOIN [gold].[dim_product] AS product
    ON sales.[product_key] = product.[product_key]
INNER JOIN [gold].[dim_product_subcategory] AS subcategory
    ON product.[product_subcategory_key] = subcategory.[product_subcategory_key]
INNER JOIN [gold].[dim_product_category] AS category
    ON subcategory.[product_category_key] = category.[product_category_key]
INNER JOIN [gold].[dim_territory] AS territory
    ON sales.[territory_key] = territory.[territory_key];
GO

CREATE OR ALTER VIEW [gold].[returns_detail]
AS
SELECT
    returns_data.[return_date],
    returns_data.[return_quantity],
    product.[product_key],
    product.[product_sku],
    product.[product_name],
    subcategory.[subcategory_name],
    category.[category_name],
    territory.[region],
    territory.[country],
    territory.[continent],
    product.[product_cost],
    CAST(
        returns_data.[return_quantity] * product.[product_cost]
        AS decimal(18, 2)
    ) AS [return_cost],
    returns_data.[run_id]
FROM [gold].[fact_returns] AS returns_data
INNER JOIN [gold].[dim_product] AS product
    ON returns_data.[product_key] = product.[product_key]
INNER JOIN [gold].[dim_product_subcategory] AS subcategory
    ON product.[product_subcategory_key] = subcategory.[product_subcategory_key]
INNER JOIN [gold].[dim_product_category] AS category
    ON subcategory.[product_category_key] = category.[product_category_key]
INNER JOIN [gold].[dim_territory] AS territory
    ON returns_data.[territory_key] = territory.[territory_key];
GO
