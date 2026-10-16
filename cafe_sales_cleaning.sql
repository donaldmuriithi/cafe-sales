-- ============================================================
-- Cafe Sales: cleaning pipeline (SQLite)
-- Source: Kaggle "Cafe Sales - Dirty Data for Cleaning Training"
-- Raw table: dirty_cafe_sales (10,000 rows) -- never modified
-- Clean table: cafe_sales_clean -- every change happens here
-- Rule: recover what the data can prove, label the rest, delete nothing
-- ============================================================

-- STEP 1. Protect the raw data: work on a copy
DROP TABLE IF EXISTS cafe_sales_clean;
CREATE TABLE cafe_sales_clean AS SELECT * FROM dirty_cafe_sales;

-- STEP 2. Profile the mess (run these to see the problem first)
SELECT "Payment Method", COUNT(*) AS total FROM cafe_sales_clean GROUP BY 1 ORDER BY total DESC;
SELECT Item,             COUNT(*) AS total FROM cafe_sales_clean GROUP BY 1 ORDER BY total DESC;
SELECT Location,         COUNT(*) AS total FROM cafe_sales_clean GROUP BY 1 ORDER BY total DESC;

-- STEP 3. Label unusable categorical values consistently as 'Unknown'
--         (ERROR, UNKNOWN and blank/NULL are all the same problem)
UPDATE cafe_sales_clean SET "Payment Method" = 'Unknown'
WHERE "Payment Method" IN ('ERROR','UNKNOWN') OR "Payment Method" IS NULL OR TRIM("Payment Method") = '';

UPDATE cafe_sales_clean SET Location = 'Unknown'
WHERE Location IN ('ERROR','UNKNOWN') OR Location IS NULL OR TRIM(Location) = '';

UPDATE cafe_sales_clean SET Item = 'Unknown'
WHERE Item IN ('ERROR','UNKNOWN') OR Item IS NULL OR TRIM(Item) = '';

-- STEP 4. Learn the rule that makes recovery possible:
--         each item has one fixed price (check: should return one row per item)
SELECT "Price Per Unit", Item, COUNT(*) AS total
FROM cafe_sales_clean
WHERE Item <> 'Unknown' AND "Price Per Unit" IS NOT NULL AND "Price Per Unit" GLOB '[0-9]*'
GROUP BY "Price Per Unit", Item
ORDER BY "Price Per Unit";

-- STEP 5. Recover Item from price where the price is unique to one item
--         (1 = Cookie, 1.5 = Tea, 2 = Coffee, 5 = Salad)
UPDATE cafe_sales_clean
SET Item = CASE "Price Per Unit"
  WHEN 1   THEN 'Cookie'
  WHEN 1.5 THEN 'Tea'
  WHEN 2   THEN 'Coffee'
  WHEN 5   THEN 'Salad'
END
WHERE Item = 'Unknown'
  AND "Price Per Unit" IN (1, 1.5, 2, 5);

-- STEP 6. Recover Price Per Unit from Item
UPDATE cafe_sales_clean
SET "Price Per Unit" = CASE Item
  WHEN 'Cookie'   THEN 1
  WHEN 'Tea'      THEN 1.5
  WHEN 'Coffee'   THEN 2
  WHEN 'Cake'     THEN 3
  WHEN 'Juice'    THEN 3
  WHEN 'Sandwich' THEN 4
  WHEN 'Smoothie' THEN 4
  WHEN 'Salad'    THEN 5
END
WHERE ("Price Per Unit" IN ('ERROR','UNKNOWN') OR "Price Per Unit" IS NULL)
  AND Item <> 'Unknown';

-- STEP 7. Rebuild Total Spent = Quantity x Price when both inputs are trustworthy
UPDATE cafe_sales_clean
SET "Total Spent" = Quantity * "Price Per Unit"
WHERE ("Total Spent" IN ('ERROR','UNKNOWN') OR "Total Spent" IS NULL)
  AND Quantity IS NOT NULL AND CAST(Quantity AS TEXT) GLOB '[0-9]*'
  AND "Price Per Unit" IS NOT NULL AND CAST("Price Per Unit" AS TEXT) GLOB '[0-9]*';

-- STEP 8. Rebuild Quantity = Total / Price
UPDATE cafe_sales_clean
SET Quantity = CAST("Total Spent" AS REAL) / "Price Per Unit"
WHERE (Quantity IS NULL OR CAST(Quantity AS TEXT) NOT GLOB '[0-9]*')
  AND "Total Spent" GLOB '[0-9]*'
  AND "Price Per Unit" IS NOT NULL AND CAST("Price Per Unit" AS TEXT) GLOB '[0-9]*';

-- STEP 9. Second pass: Price = Total / Quantity, then Item from the new price
UPDATE cafe_sales_clean
SET "Price Per Unit" = 1.0 * "Total Spent" / Quantity
WHERE ("Price Per Unit" IS NULL OR CAST("Price Per Unit" AS TEXT) NOT GLOB '[0-9]*')
  AND "Total Spent" GLOB '[0-9]*'
  AND Quantity IS NOT NULL AND CAST(Quantity AS TEXT) GLOB '[0-9]*';

UPDATE cafe_sales_clean
SET Item = CASE "Price Per Unit"
  WHEN 1 THEN 'Cookie' WHEN 1.5 THEN 'Tea' WHEN 2 THEN 'Coffee' WHEN 5 THEN 'Salad'
END
WHERE Item = 'Unknown' AND "Price Per Unit" IN (1, 1.5, 2, 5);

-- STEP 10. Standardise dates: DD/MM/YYYY -> YYYY-MM-DD, bad dates become real NULLs
UPDATE cafe_sales_clean
SET "Transaction Date" =
  substr("Transaction Date", 7, 4) || '-' ||
  substr("Transaction Date", 4, 2) || '-' ||
  substr("Transaction Date", 1, 2)
WHERE "Transaction Date" LIKE '__/__/____';

UPDATE cafe_sales_clean
SET "Transaction Date" = NULL
WHERE "Transaction Date" NOT LIKE '____-__-__' OR "Transaction Date" IS NULL;

-- STEP 11. Flag rows where a numeric column could not be recovered (kept, not deleted)
ALTER TABLE cafe_sales_clean ADD COLUMN needs_review INTEGER DEFAULT 0;

UPDATE cafe_sales_clean
SET needs_review = 1
WHERE Quantity IS NULL OR CAST(Quantity AS TEXT) NOT GLOB '[0-9]*'
   OR "Total Spent" IS NULL OR "Total Spent" NOT GLOB '[0-9]*'
   OR "Price Per Unit" IS NULL OR CAST("Price Per Unit" AS TEXT) NOT GLOB '[0-9]*';

-- STEP 12. Verify
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT "Transaction ID") AS distinct_ids,
       SUM(needs_review) AS flagged,
       SUM(Item = 'Unknown') AS unknown_items,
       SUM("Transaction Date" IS NULL) AS undated
FROM cafe_sales_clean;
