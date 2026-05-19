-- Prevent output from including "Rows Affected" lines
SET NOCOUNT ON;

-- This query grabs the ALMOST same data I've been manually entering in data.csv for that NewProductBigCommerce.bat script
-- I need to look at this closer still to see exactly what the difference is. Seems to be related to not having UPC barcodes set up or maybe the primary barcode not being set to the style
-- The first half of this query gets the product-level row (1 per product)
-- The second half of this query grabs all sku/variant-level data that BigCommerce needs for all sizes/widths/etc
-- This query is still a WIP so don't trust it fully yet
WITH RankedSkuRPT AS (SELECT skurpt.STYLE AS Product, 
        '' AS [Search Keywords], 
        skurpt.Description AS Name, 
        skurpt.Price, 
        (CASE 
            WHEN skurpt.TYP LIKE '%SOCKS%' OR skurpt.TYP LIKE '%INSOL%' THEN '2'
            WHEN skurpt.OF2 = 'FOOT' THEN '1'
            WHEN skurpt.OF2 = 'APPAR' THEN '3'
            WHEN skurpt.OF2 = 'PET' THEN '4'
            ELSE '4'
        END) AS [Item Type], 
        '' AS UPC, 
        '' AS [Primary Barcode], 
        '' AS Size, 
        '' AS width,
        '' AS Color, 
        CONCAT('"', skurpt.BRAND, '"') AS [Brand],
        CONCAT('"', skurpt.OF6, '"') AS [PrefVendor],
        ROW_NUMBER() OVER (
            PARTITION BY skurpt.STYLE 
            ORDER BY skurpt.Description ASC -- Or any column to pick which row is "first"
        ) AS RowNum
FROM VW_TICKETS skurpt
INNER JOIN TB_STYLES styles
ON styles.STYLE_ID = skurpt.STYLE_ID
WHERE skurpt.STYLE IN ($(Products))
AND skurpt.STORE_ID = 1
AND styles.STATUS_FINISH='N'
AND skurpt.OF1 NOT IN ('NSTOCK', 'DISCO', 'SO', ''))
SELECT 
    Product, 
    [Search Keywords], 
    Name, 
    Price, 
    [Item Type], 
    UPC, 
    [Primary Barcode], 
    Size, 
    width,
    Color, 
    Brand,
    PrefVendor,
    1 AS RowPriority
FROM RankedSkuRPT
WHERE RowNum = 1
UNION ALL
SELECT  tickets.STYLE AS Product, 
        '' AS [Search Keywords], 
        '' AS Name, 
        tickets.Price, 
        '' AS [Item Type], 
        ISNULL(CAST(RTRIM(lookups.LOOKUP) AS VARCHAR), '') AS UPC,  
        CAST(RTRIM(tickets.LOOKUP) AS VARCHAR) AS [Primary Barcode], 
        ISNULL(NULLIF(REPLACE(REPLACE(UPPER(tickets.SIZ), '/', ''), '_', ''), 'NA'), 'One Size') AS Size,
        ISNULL(tickets.ATTR2, '') AS width,
        ISNULL(NULLIF(REPLACE(REPLACE(UPPER(tickets.ATTR1), '/', ''), '_', ''), 'NA'), '') AS Color,
        CONCAT('"', tickets.BRAND, '"') AS [Brand],
        CONCAT('"', tickets.OF6, '"') AS [PrefVendor],
        0 AS RowPriority
FROM VW_TICKETS tickets
INNER JOIN TB_STYLES styles
ON styles.STYLE_ID = tickets.STYLE_ID
LEFT JOIN TB_SKU_LOOKUPS lookups
ON tickets.SKU_ID = lookups.SKU_ID
AND lookups.TYP = 1
WHERE tickets.STYLE IN ($(Products))
AND tickets.STORE_ID = 1
AND styles.STATUS_FINISH='N'
AND tickets.OF1 NOT IN ('NSTOCK', 'DISCO', 'SO', '')
ORDER BY Brand, PRODUCT, Color, Size, width, RowPriority DESC;
