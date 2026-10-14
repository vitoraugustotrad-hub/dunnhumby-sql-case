-- =====================================================================
-- q10_private_label.sql
--
-- Business question: Does the private-label share fall as household income
--                    rises?
-- Why it matters:    Private label usually carries higher margin. If
--                    high-income customers avoid it, there's room for a
--                    premium private-label line; if lower income relies on
--                    it, it's a retention lever for that group.
-- Approach:
--   1. band:      groups the 12 income bands into 6 (some have only 5-11
--                 households) and creates a numeric order — text sorts
--                 wrong ('100-124K' < '15-24K')
--   2. hh_spend:  total and private-label sales per household
--   3. Query A:   share by band in TWO ways:
--                 - pooled:  sum Private / sum total (weights big spenders)
--                 - average: mean of each household's share (1 household = 1 vote)
--   4. Query B:   the same reading within each department, to check the
--                 effect isn't just category mix
-- Assumptions / filters:
--   - Base: vw_transactions; sales = SUM(sales_value)
--   - ONLY the 801 households with demographics (55.8% of sales). They are
--     not a random sample of the 2,500 — conclusions apply to this group.
-- Checks:
--   - Households across bands = 801
--   - Overall share of the 801 is close to the full base (~21%)
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: private-label share by income band
-- ---------------------------------------------------------------------
WITH band AS (
    SELECT household_key,
           CASE
               WHEN income_desc IN ('Under 15K', '15-24K')              THEN 1
               WHEN income_desc IN ('25-34K', '35-49K')                 THEN 2
               WHEN income_desc =   '50-74K'                            THEN 3
               WHEN income_desc =   '75-99K'                            THEN 4
               WHEN income_desc IN ('100-124K', '125-149K')             THEN 5
               ELSE                                                          6  -- 150K+
           END AS sort_order,
           CASE
               WHEN income_desc IN ('Under 15K', '15-24K')              THEN '< 25K'
               WHEN income_desc IN ('25-34K', '35-49K')                 THEN '25-49K'
               WHEN income_desc =   '50-74K'                            THEN '50-74K'
               WHEN income_desc =   '75-99K'                            THEN '75-99K'
               WHEN income_desc IN ('100-124K', '125-149K')             THEN '100-149K'
               ELSE                                                          '150K+'
           END AS income_band
    FROM hh_demographic
),
hh_spend AS (
    SELECT t.household_key,
           SUM(t.sales_value)                                    AS sales,
           SUM(t.sales_value) FILTER (WHERE t.brand = 'Private') AS private_sales
    FROM vw_transactions t
    WHERE EXISTS (SELECT 1 FROM hh_demographic h
                  WHERE h.household_key = t.household_key)
    GROUP BY t.household_key
)
SELECT b.income_band,
       COUNT(*)                                                         AS households,
       ROUND(AVG(s.sales))                                              AS avg_spend,
       ROUND(100.0 * SUM(s.private_sales) / SUM(s.sales), 1)            AS pooled_share,
       ROUND(100.0 * AVG(COALESCE(s.private_sales, 0) / s.sales), 1)    AS avg_hh_share
FROM hh_spend s
JOIN band b USING (household_key)
GROUP BY b.sort_order, b.income_band
ORDER BY b.sort_order;


-- ---------------------------------------------------------------------
-- Query B: mix control — share by department x band
-- (only departments with a relevant private-label share)
-- ---------------------------------------------------------------------
WITH band AS (
    SELECT household_key,
           CASE
               WHEN income_desc IN ('Under 15K', '15-24K', '25-34K', '35-49K') THEN '1. < 50K'
               WHEN income_desc IN ('50-74K', '75-99K')                        THEN '2. 50-99K'
               ELSE                                                                 '3. 100K+'
           END AS income_band
    FROM hh_demographic
),
dept AS (
    SELECT t.department, b.income_band,
           SUM(t.sales_value)                                    AS sales,
           SUM(t.sales_value) FILTER (WHERE t.brand = 'Private') AS private_sales
    FROM vw_transactions t
    JOIN band b USING (household_key)
    GROUP BY t.department, b.income_band
)
SELECT department,
       ROUND(100.0 * SUM(private_sales) FILTER (WHERE income_band = '1. < 50K')
                   / SUM(sales)         FILTER (WHERE income_band = '1. < 50K'), 1)  AS "< 50K",
       ROUND(100.0 * SUM(private_sales) FILTER (WHERE income_band = '2. 50-99K')
                   / SUM(sales)         FILTER (WHERE income_band = '2. 50-99K'), 1) AS "50-99K",
       ROUND(100.0 * SUM(private_sales) FILTER (WHERE income_band = '3. 100K+')
                   / SUM(sales)         FILTER (WHERE income_band = '3. 100K+'), 1)  AS "100K+",
       ROUND(SUM(sales))                                                             AS total_sales
FROM dept
GROUP BY department
HAVING SUM(sales) > 50000
   AND SUM(private_sales) > 0.05 * SUM(sales)
ORDER BY total_sales DESC;
