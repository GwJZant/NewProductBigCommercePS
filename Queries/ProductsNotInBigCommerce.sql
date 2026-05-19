-- Grabs all products NOT in BigCommerce with > 0 On Hand in all 4 stores combined
-- Fields are formatted to be CSV-compliant
-- Excludes SEASONs: NSTOCK, SO, DISCO, [BLANK]
-- Excludes IMPULSE items (energy drinks, gatorades, snacks, etc)
-- Excludes Inactive items
SELECT	'MKT GROUP' AS [MKT GROUP], 
		'Dept.' AS [Dept.], 
		'Product Type' AS [Product Type], 
		'Subtype 1' AS [Subtype 1], 
		'Brand' AS [Brand],  
		'PRODUCT' AS [PRODUCT],  
		'PRODUCT Formatted' AS [PRODUCT Formatted], 
		'Description' AS [Description], 
		'Retail Price' AS [Retail Price],  
		'SEASON' AS [SEASON],  
		'First Rcvd' AS [First Rcvd], 
		'Added' AS [Added], 
		'Needs Description' AS [Needs Description], 
		'Needs Photo' AS [Needs Photo], 
		'Notes' AS [Notes]
UNION ALL
SELECT  [outer].[MKT GROUP],
		[outer].[Dept.],
		[outer].[Product Type],
		[outer].[Subtype 1],
		[outer].[Brand],
		[outer].[PRODUCT],
		[outer].[PRODUCT Formatted],
		[outer].[Description],
		[outer].[Retail Price],
		[outer].[SEASON],
		[outer].[First Rcvd],
		[outer].[Added],
		[outer].[Needs Description],
		[outer].[Needs Photo],
		[outer].[Notes]
FROM
(SELECT	CONCAT('"', vw.OF2, '"') AS [MKT GROUP], 
		CONCAT('"', vw.DEPT, '"') AS [Dept.], 
		CONCAT('"', vw.TYP, '"') AS [Product Type], 
		CONCAT('"', vw.SUBTYP_1, '"') AS [Subtype 1], 
		CONCAT('"', vw.BRAND, '"') AS [Brand], 
		vw.STYLE AS [PRODUCT], 
		--CONCAT('''', vw.STYLE, '''') AS [PRODUCT Formatted], -- Excel will chop off leading/trailing zeroes so this preserves a string-formatted product code
		CONCAT('"', REPLACE(vw.DESCRIPTION, '"', '""'), '"') AS [Description], 
		CAST(vw.PRICE AS VARCHAR) AS [Retail Price], 
		vw.OF1 AS [SEASON], 
		ISNULL(CONVERT(VARCHAR(25), vw.FIRST_RCVD, 101), '########') AS [First Rcvd],
		'' AS [Added],
		'' AS [Needs Description],
		'' AS [Needs Photo],
		'' AS [Notes]
FROM VW_SKU_RPT vw
WHERE vw.STYLE NOT IN (SELECT StyleID FROM ##BigCommerceList)
AND vw.OF1 NOT IN ('NSTOCK', 'DISCO', 'SO', '')
AND vw.DEPT NOT LIKE '%IMPULSE%'
AND EXISTS (SELECT styles.STATUS_FINISH FROM TB_STYLES AS styles WHERE styles.STYLE = vw.STYLE AND styles.STATUS_FINISH = 'N' AND styles.DESCRIPTION = vw.DESCRIPTION)
GROUP BY vw.OF2, vw.DEPT, vw.TYP, vw.SUBTYP_1, vw.BRAND, vw.STYLE, vw.DESCRIPTION, vw.PRICE, vw.OF1, vw.FIRST_RCVD
HAVING SUM(vw.QOH) > 0
ORDER BY [BRAND], [SEASON], [PRODUCT] OFFSET 0 ROWS) AS [outer];

