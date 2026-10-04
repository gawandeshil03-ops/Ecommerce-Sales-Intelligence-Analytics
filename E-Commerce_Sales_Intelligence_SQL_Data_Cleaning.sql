/*
===============================================================================
PROJECT: E-COMMERCE SALES INTELLIGENCE
TECH STACK: SQL SERVER + T-SQL + POWER BI

PURPOSE
-------
SQL is used as the data preparation layer:
    Raw Orders + Raw Details
            ↓
      SQL Staging Tables
            ↓
      Data Quality Checks
            ↓
     Cleaning & Validation
            ↓
       Transformation
            ↓
   vw_Ecommerce_Sales
            ↓
       Power BI Dashboard

NOTE
----
This script is designed for the Orders + Details structure used by the
E-Commerce Sales Intelligence Power BI project.

Before using BULK INSERT, update the CSV file paths for your local machine.
===============================================================================
*/

-- ============================================================================
-- 1. DATABASE
-- ============================================================================

IF DB_ID('ECommerceSalesIntelligence') IS NULL
    CREATE DATABASE ECommerceSalesIntelligence;
GO

USE ECommerceSalesIntelligence;
GO


-- ============================================================================
-- 2. RAW / STAGING TABLES
-- ============================================================================

IF OBJECT_ID('dbo.Raw_Orders', 'U') IS NOT NULL
    DROP TABLE dbo.Raw_Orders;
GO

CREATE TABLE dbo.Raw_Orders
(
    OrderID       NVARCHAR(50),
    OrderDateRaw  NVARCHAR(50),
    CustomerName  NVARCHAR(150),
    StateRaw      NVARCHAR(100),
    City          NVARCHAR(100)
);
GO


IF OBJECT_ID('dbo.Raw_Details', 'U') IS NOT NULL
    DROP TABLE dbo.Raw_Details;
GO

CREATE TABLE dbo.Raw_Details
(
    OrderID        NVARCHAR(50),
    AmountRaw      NVARCHAR(50),
    ProfitRaw      NVARCHAR(50),
    QuantityRaw    NVARCHAR(50),
    CategoryRaw    NVARCHAR(100),
    SubCategoryRaw NVARCHAR(100),
    PaymentModeRaw NVARCHAR(100),
    AOVRaw         NVARCHAR(50)
);
GO


-- ============================================================================
-- 3. OPTIONAL CSV IMPORT
-- ============================================================================
-- Update the paths before uncommenting.
--
-- BULK INSERT dbo.Raw_Orders
-- FROM 'C:\Data\ECommerce\Orders.csv'
-- WITH
-- (
--     FIRSTROW = 2,
--     FIELDTERMINATOR = ',',
--     ROWTERMINATOR = '0x0a',
--     TABLOCK
-- );
--
-- BULK INSERT dbo.Raw_Details
-- FROM 'C:\Data\ECommerce\Details.csv'
-- WITH
-- (
--     FIRSTROW = 2,
--     FIELDTERMINATOR = ',',
--     ROWTERMINATOR = '0x0a',
--     TABLOCK
-- );
-- GO


-- ============================================================================
-- 4. DATA QUALITY PROFILING
-- ============================================================================

-- Row counts
SELECT 'Raw_Orders' AS TableName, COUNT(*) AS RowCount
FROM dbo.Raw_Orders
UNION ALL
SELECT 'Raw_Details', COUNT(*)
FROM dbo.Raw_Details;
GO


-- Missing / blank values in Orders
SELECT
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(OrderID)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingOrderID,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(OrderDateRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingOrderDate,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(CustomerName)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingCustomerName,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(StateRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingState,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(City)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingCity
FROM dbo.Raw_Orders;
GO


-- Missing / blank values in Details
SELECT
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(OrderID)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingOrderID,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(AmountRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingAmount,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(ProfitRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingProfit,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(QuantityRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingQuantity,

    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(CategoryRaw)), '') IS NULL
             THEN 1 ELSE 0 END) AS MissingCategory
FROM dbo.Raw_Details;
GO


-- ============================================================================
-- 5. CLEAN ORDERS
-- ============================================================================
-- Operations:
--   • Trim whitespace
--   • Convert OrderDate to DATE
--   • Convert blank strings to NULL
--   • Remove records without OrderID
--   • Deduplicate OrderID records

IF OBJECT_ID('dbo.Clean_Orders', 'U') IS NOT NULL
    DROP TABLE dbo.Clean_Orders;
GO

WITH CleanedOrders AS
(
    SELECT
        NULLIF(LTRIM(RTRIM(OrderID)), '') AS OrderID,

        TRY_CONVERT(
            DATE,
            NULLIF(LTRIM(RTRIM(OrderDateRaw)), '')
        ) AS OrderDate,

        NULLIF(LTRIM(RTRIM(CustomerName)), '') AS CustomerName,

        NULLIF(LTRIM(RTRIM(StateRaw)), '') AS StateName,

        NULLIF(LTRIM(RTRIM(City)), '') AS City,

        ROW_NUMBER() OVER
        (
            PARTITION BY NULLIF(LTRIM(RTRIM(OrderID)), '')
            ORDER BY
                CASE
                    WHEN TRY_CONVERT(
                        DATE,
                        NULLIF(LTRIM(RTRIM(OrderDateRaw)), '')
                    ) IS NULL
                    THEN 1 ELSE 0
                END,
                OrderDateRaw
        ) AS rn

    FROM dbo.Raw_Orders
)
SELECT
    OrderID,
    OrderDate,
    CustomerName,
    StateName,
    City
INTO dbo.Clean_Orders
FROM CleanedOrders
WHERE rn = 1
  AND OrderID IS NOT NULL;
GO


-- ============================================================================
-- 6. CLEAN ORDER DETAILS
-- ============================================================================
-- Operations:
--   • Trim whitespace
--   • Convert Amount / Profit to DECIMAL
--   • Convert Quantity to INT
--   • Standardize category/payment text
--   • Calculate AOV from Amount / Quantity when possible

IF OBJECT_ID('dbo.Clean_Details', 'U') IS NOT NULL
    DROP TABLE dbo.Clean_Details;
GO

WITH CleanedDetails AS
(
    SELECT
        NULLIF(LTRIM(RTRIM(OrderID)), '') AS OrderID,

        TRY_CONVERT(
            DECIMAL(18,2),
            NULLIF(
                REPLACE(
                    REPLACE(LTRIM(RTRIM(AmountRaw)), ',', ''),
                    '₹',
                    ''
                ),
                ''
            )
        ) AS Amount,

        TRY_CONVERT(
            DECIMAL(18,2),
            NULLIF(
                REPLACE(
                    REPLACE(LTRIM(RTRIM(ProfitRaw)), ',', ''),
                    '₹',
                    ''
                ),
                ''
            )
        ) AS Profit,

        TRY_CONVERT(
            INT,
            NULLIF(LTRIM(RTRIM(QuantityRaw)), '')
        ) AS Quantity,

        NULLIF(LTRIM(RTRIM(CategoryRaw)), '') AS Category,

        NULLIF(LTRIM(RTRIM(SubCategoryRaw)), '') AS SubCategory,

        NULLIF(LTRIM(RTRIM(PaymentModeRaw)), '') AS PaymentMode,

        TRY_CONVERT(
            DECIMAL(18,2),
            NULLIF(
                REPLACE(
                    REPLACE(LTRIM(RTRIM(AOVRaw)), ',', ''),
                    '₹',
                    ''
                ),
                ''
            )
        ) AS SourceAOV

    FROM dbo.Raw_Details
)
SELECT
    OrderID,
    Amount,
    Profit,
    Quantity,
    Category,
    SubCategory,
    PaymentMode,

    CASE
        WHEN Quantity > 0
            THEN CAST(Amount / Quantity AS DECIMAL(18,2))
        ELSE SourceAOV
    END AS AOV

INTO dbo.Clean_Details
FROM CleanedDetails
WHERE OrderID IS NOT NULL;
GO


-- ============================================================================
-- 7. VALIDATION CHECKS
-- ============================================================================

-- Invalid dates
SELECT *
FROM dbo.Clean_Orders
WHERE OrderDate IS NULL;
GO


-- Invalid quantities / amounts
SELECT *
FROM dbo.Clean_Details
WHERE Quantity IS NULL
   OR Quantity <= 0
   OR Amount IS NULL;
GO


-- Duplicate Order IDs after cleaning
SELECT
    OrderID,
    COUNT(*) AS DuplicateCount
FROM dbo.Clean_Orders
GROUP BY OrderID
HAVING COUNT(*) > 1;
GO


-- ============================================================================
-- 8. ANALYTICS-READY VIEW FOR POWER BI
-- ============================================================================

IF OBJECT_ID('dbo.vw_Ecommerce_Sales', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Ecommerce_Sales;
GO

CREATE VIEW dbo.vw_Ecommerce_Sales
AS
SELECT
    d.OrderID,

    o.OrderDate,
    YEAR(o.OrderDate) AS OrderYear,
    MONTH(o.OrderDate) AS OrderMonth,
    DATEPART(QUARTER, o.OrderDate) AS OrderQuarter,

    o.CustomerName,
    o.StateName AS State,
    o.City,

    d.Category,
    d.SubCategory,
    d.PaymentMode,

    d.Amount,
    d.Profit,
    d.Quantity,
    d.AOV,

    CASE
        WHEN d.Amount > 0
        THEN CAST(
            (d.Profit / d.Amount) * 100.0
            AS DECIMAL(10,2)
        )
        ELSE NULL
    END AS ProfitMarginPct

FROM dbo.Clean_Details AS d

INNER JOIN dbo.Clean_Orders AS o
    ON d.OrderID = o.OrderID

WHERE d.Amount IS NOT NULL
  AND d.Quantity IS NOT NULL
  AND d.Quantity > 0;
GO


-- ============================================================================
-- 9. POWER BI SOURCE CHECK
-- ============================================================================

SELECT TOP 100 *
FROM dbo.vw_Ecommerce_Sales
ORDER BY OrderDate, OrderID;
GO


-- ============================================================================
-- 10. KPI VALIDATION
-- ============================================================================

SELECT
    COUNT(DISTINCT OrderID) AS TotalOrders,
    SUM(Amount) AS TotalSales,
    SUM(Quantity) AS TotalQuantity,
    SUM(Profit) AS TotalProfit,

    CAST(
        SUM(Profit) /
        NULLIF(SUM(Amount), 0) * 100
        AS DECIMAL(10,2)
    ) AS OverallProfitMarginPct

FROM dbo.vw_Ecommerce_Sales;
GO


-- ============================================================================
-- 11. CATEGORY PERFORMANCE
-- ============================================================================

SELECT
    Category,
    SUM(Amount) AS TotalSales,
    SUM(Profit) AS TotalProfit,
    SUM(Quantity) AS TotalQuantity
FROM dbo.vw_Ecommerce_Sales
GROUP BY Category
ORDER BY TotalSales DESC;
GO


-- ============================================================================
-- 12. STATE PERFORMANCE
-- ============================================================================

SELECT
    State,
    SUM(Amount) AS TotalSales,
    SUM(Profit) AS TotalProfit,
    SUM(Quantity) AS TotalQuantity
FROM dbo.vw_Ecommerce_Sales
GROUP BY State
ORDER BY TotalSales DESC;
GO


-- ============================================================================
-- 13. PAYMENT MODE PERFORMANCE
-- ============================================================================

SELECT
    PaymentMode,
    SUM(Amount) AS TotalSales,
    SUM(Profit) AS TotalProfit,
    SUM(Quantity) AS TotalQuantity
FROM dbo.vw_Ecommerce_Sales
GROUP BY PaymentMode
ORDER BY TotalSales DESC;
GO


-- ============================================================================
-- 14. TOP CUSTOMERS
-- ============================================================================

SELECT TOP 10
    CustomerName,
    SUM(Amount) AS TotalSales,
    SUM(Profit) AS TotalProfit,
    SUM(Quantity) AS TotalQuantity
FROM dbo.vw_Ecommerce_Sales
GROUP BY CustomerName
ORDER BY TotalSales DESC;
GO


/*
===============================================================================
POWER BI CONNECTION

Power BI Desktop
    ↓
Get Data
    ↓
SQL Server
    ↓
Database: ECommerceSalesIntelligence
    ↓
View: dbo.vw_Ecommerce_Sales
    ↓
Load / Transform
    ↓
Dashboard

INTERVIEW SUMMARY

"I built E-Commerce Sales Intelligence as a two-layer analytics solution.
I used SQL Server as the data preparation layer to profile, clean and
transform the Orders and Details data. I handled missing values, invalid
data types, duplicate records and inconsistent text, then created derived
metrics such as AOV and profit margin. I exposed the cleaned dataset through
an analytics-ready SQL view and connected that view to Power BI for
interactive business intelligence and sales analysis."

===============================================================================
*/
