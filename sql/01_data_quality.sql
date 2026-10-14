-- =====================================================================
-- 01_data_quality.sql — Dunnhumby "The Complete Journey" (PostgreSQL)
--
-- Goal: understand the data BEFORE answering business questions.
-- Each block answers "can I trust this?" and its result becomes a line
-- in the "Data quality notes" section of the README.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Volume: row counts and distinct entities
--    Check: ~2.6M rows, 2,500 households, 102 weeks, 711 days
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                        AS row_count,
    COUNT(DISTINCT household_key)   AS households,
    COUNT(DISTINCT basket_id)       AS baskets,
    COUNT(DISTINCT product_id)      AS products,
    COUNT(DISTINCT store_id)        AS stores,
    MIN(day)  AS min_day,  MAX(day)  AS max_day,
    MIN(week_no) AS min_week, MAX(week_no) AS max_week,
    SUM(sales_value)                AS total_sales
FROM transaction_data;


-- ---------------------------------------------------------------------
-- 2. Nulls in key columns (anything > 0 is a problem)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE household_key IS NULL) AS null_household,
    COUNT(*) FILTER (WHERE basket_id     IS NULL) AS null_basket,
    COUNT(*) FILTER (WHERE product_id    IS NULL) AS null_product,
    COUNT(*) FILTER (WHERE day           IS NULL) AS null_day,
    COUNT(*) FILTER (WHERE sales_value   IS NULL) AS null_sales
FROM transaction_data;


-- ---------------------------------------------------------------------
-- 3. Duplicates
-- 3a. Fully identical rows in transaction_data
--     (could be legitimate: same item scanned twice — document it)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS duplicate_groups, SUM(n - 1) AS extra_rows
FROM (
    SELECT COUNT(*) AS n
    FROM transaction_data
    GROUP BY household_key, basket_id, day, product_id, quantity, sales_value,
             store_id, retail_disc, trans_time, week_no, coupon_disc, coupon_match_disc
    HAVING COUNT(*) > 1
) d;

-- 3b. A basket should belong to ONE household, ONE day and ONE store
SELECT
    COUNT(*) FILTER (WHERE n_hh     > 1) AS baskets_multi_household,
    COUNT(*) FILTER (WHERE n_days   > 1) AS baskets_multi_day,
    COUNT(*) FILTER (WHERE n_stores > 1) AS baskets_multi_store
FROM (
    SELECT basket_id,
           COUNT(DISTINCT household_key) AS n_hh,
           COUNT(DISTINCT day)           AS n_days,
           COUNT(DISTINCT store_id)      AS n_stores
    FROM transaction_data
    GROUP BY basket_id
) b;

-- 3c. Same household receiving the same campaign twice
SELECT COUNT(*) AS duplicate_pairs
FROM (
    SELECT household_key, campaign
    FROM campaign_table
    GROUP BY household_key, campaign
    HAVING COUNT(*) > 1
) d;


-- ---------------------------------------------------------------------
-- 4. Referential integrity (orphans), via NOT EXISTS anti-joins
-- ---------------------------------------------------------------------
SELECT 'transaction with product missing from catalog' AS check_name, COUNT(*) AS n
FROM transaction_data t
WHERE NOT EXISTS (SELECT 1 FROM product p WHERE p.product_id = t.product_id)
UNION ALL
SELECT 'redemption of a non-existent coupon', COUNT(*)
FROM coupon_redempt r
WHERE NOT EXISTS (SELECT 1 FROM coupon c WHERE c.coupon_upc = r.coupon_upc
                                          AND c.campaign   = r.campaign)
UNION ALL
SELECT 'redemption by a household that did not receive the campaign', COUNT(*)
FROM coupon_redempt r
WHERE NOT EXISTS (SELECT 1 FROM campaign_table ct
                  WHERE ct.household_key = r.household_key
                    AND ct.campaign      = r.campaign)
UNION ALL
SELECT 'campaign_table row with no campaign description', COUNT(*)
FROM campaign_table ct
WHERE NOT EXISTS (SELECT 1 FROM campaign_desc cd WHERE cd.campaign = ct.campaign)
UNION ALL
SELECT 'demographics for a household with no transactions', COUNT(*)
FROM hh_demographic h
WHERE NOT EXISTS (SELECT 1 FROM transaction_data t WHERE t.household_key = h.household_key);


-- ---------------------------------------------------------------------
-- 5. Time consistency
-- 5a. Do DAY and WEEK_NO move together? Each week should span 7 days.
-- ---------------------------------------------------------------------
SELECT week_no, MIN(day) AS first_day, MAX(day) AS last_day,
       MAX(day) - MIN(day) + 1 AS span_days
FROM transaction_data
GROUP BY week_no
HAVING MAX(day) - MIN(day) + 1 <> 7
ORDER BY week_no;

-- 5b. Is TRANS_TIME a valid HHMM? (hour 0-23, minute 0-59)
SELECT COUNT(*) AS invalid_times
FROM transaction_data
WHERE trans_time / 100 > 23 OR trans_time % 100 > 59;

-- 5c. Redemptions outside the campaign window
SELECT cd.description, COUNT(*) AS redemptions_outside_window
FROM coupon_redempt r
JOIN campaign_desc cd USING (campaign)
WHERE r.day NOT BETWEEN cd.start_day AND cd.end_day
GROUP BY cd.description;


-- ---------------------------------------------------------------------
-- 6. Suspicious amounts and quantities
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE quantity = 0)                     AS qty_zero,
    COUNT(*) FILTER (WHERE sales_value = 0)                  AS sales_zero,
    COUNT(*) FILTER (WHERE quantity = 0 AND sales_value > 0) AS sales_without_qty,
    COUNT(*) FILTER (WHERE sales_value < 0)                  AS negative_sales,
    COUNT(*) FILTER (WHERE retail_disc > 0)                  AS positive_discount,
    COUNT(*) FILTER (WHERE coupon_disc > 0)                  AS positive_coupon,
    COUNT(*) FILTER (WHERE coupon_match_disc <> 0
                       AND coupon_disc = 0)                  AS match_without_coupon
FROM transaction_data;


-- ---------------------------------------------------------------------
-- 7. Quantity outliers: where are they?
--    Hypothesis: fuel (quantity = gallons / pump units)
-- ---------------------------------------------------------------------
SELECT p.department, p.commodity_desc,
       COUNT(*)                  AS row_count,
       MAX(t.quantity)           AS max_qty,
       ROUND(AVG(t.quantity), 1) AS avg_qty,
       SUM(t.sales_value)        AS sales
FROM transaction_data t
JOIN product p USING (product_id)
WHERE t.quantity > 100
GROUP BY p.department, p.commodity_desc
ORDER BY row_count DESC
LIMIT 10;

-- Share of sales from fuel and uncategorized items
SELECT
    CASE WHEN p.department = 'KIOSK-GAS'               THEN 'KIOSK-GAS'
         WHEN p.commodity_desc LIKE 'COUPON/MISC%'     THEN 'COUPON/MISC'
         WHEN p.department IN ('MISC. TRANS.', 'MISC SALES TRAN', ' ')
              OR p.commodity_desc = 'NO COMMODITY DESCRIPTION'
                                                       THEN 'uncategorized'
         ELSE 'regular products' END AS item_group,
    COUNT(*) AS row_count,
    ROUND(100.0 * SUM(t.sales_value) / SUM(SUM(t.sales_value)) OVER (), 2) AS pct_sales
FROM transaction_data t
JOIN product p USING (product_id)
GROUP BY 1
ORDER BY pct_sales DESC;


-- ---------------------------------------------------------------------
-- 8. Demographic coverage: what share of the business does it cover?
--    Matters for every income/age analysis.
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT t.household_key)                                  AS households,
    COUNT(DISTINCT t.household_key) FILTER (WHERE h.household_key IS NOT NULL)
                                                                     AS with_demographics,
    ROUND(100.0 * SUM(t.sales_value) FILTER (WHERE h.household_key IS NOT NULL)
                / SUM(t.sales_value), 1)                             AS pct_sales_covered
FROM transaction_data t
LEFT JOIN hh_demographic h USING (household_key);


-- ---------------------------------------------------------------------
-- 9. Weekly activity: are the first/last weeks incomplete?
--    (the panel may have onboarded households gradually)
-- ---------------------------------------------------------------------
SELECT week_no,
       COUNT(DISTINCT household_key) AS active_households,
       ROUND(SUM(sales_value))       AS sales
FROM transaction_data
GROUP BY week_no
ORDER BY week_no;


-- ---------------------------------------------------------------------
-- 10. Weight of discounts (decides which sales metric to use)
--     sales_value = amount the retailer receives for the line.
--     Discounts are NEGATIVE; sales_value - retail_disc - coupon_match_disc
--     is the value BEFORE discounts (shelf price x qty).
--     Case decision: sales = SUM(sales_value).
-- ---------------------------------------------------------------------
SELECT
    ROUND(SUM(sales_value))                                         AS sales,
    ROUND(-SUM(retail_disc))                                        AS store_discount,
    ROUND(-SUM(coupon_disc))                                        AS coupon_discount,
    ROUND(-SUM(coupon_match_disc))                                  AS coupon_match_discount,
    ROUND(100.0 * -SUM(retail_disc)
          / SUM(sales_value - retail_disc - coupon_match_disc), 1)  AS pct_store_disc_of_gross,
    ROUND(100.0 * COUNT(*) FILTER (WHERE retail_disc < 0) / COUNT(*), 1)
                                                                    AS pct_rows_discounted
FROM transaction_data;
