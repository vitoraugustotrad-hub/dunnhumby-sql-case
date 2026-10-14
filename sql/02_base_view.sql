-- =====================================================================
-- 02_base_view.sql — clean base used by every question (q01..q10)
--
-- Filters (justified in 01_data_quality.sql):
--   - Excludes fuel (department KIOSK-GAS) and miscellaneous transactions
--     (MISC SALES TRAN / MISC. TRANS.): quantity reaches ~90k
--   - Excludes coupon and uncategorized items
--   - Excludes rows with quantity = 0 or sales_value = 0
-- Check: 2,545,038 rows, sales 7,377,350, max quantity = 144
-- =====================================================================

CREATE OR REPLACE VIEW vw_transactions AS
SELECT t.*,
       p.department,
       p.commodity_desc,
       p.sub_commodity_desc,
       p.brand
FROM transaction_data t
JOIN product p USING (product_id)
WHERE p.department     NOT IN ('KIOSK-GAS', 'MISC SALES TRAN', 'MISC. TRANS.')
  AND p.commodity_desc NOT IN ('COUPON/MISC ITEMS', 'NO COMMODITY DESCRIPTION')
  AND t.quantity    > 0
  AND t.sales_value > 0;

-- Check
SELECT COUNT(*)                  AS row_count,
       ROUND(SUM(sales_value))   AS sales,
       MAX(quantity)             AS max_qty
FROM vw_transactions;
