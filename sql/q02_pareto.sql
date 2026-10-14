-- =====================================================================
-- q02_pareto.sql
--
-- Business question: What % of households generates 80% of sales?
--                    How is sales distributed across customers?
-- Why it matters:    If sales is concentrated, losing a few customers is
--                    expensive -> justifies a loyalty program focused on
--                    the top instead of blanket actions.
-- Approach:
--   1. hh_spend:  total sales per household (2 years)
--   2. ranking:   sort from highest to lowest and compute running sales
--                 with SUM() OVER (ROWS ...)
--   3. answer:    first household where the running total crosses 80%
--   4. (Query B)  distribution by decile with NTILE(10)
-- Assumptions / filters:
--   - Base: vw_transactions (no fuel, coupons/misc, zero qty or sales)
--   - Sales = SUM(sales_value)
--   - Full period (weeks 1-102); households that joined the panel late
--     have fewer weeks of purchases (see limitations)
-- Checks:
--   - Sum of deciles = total sales of the view (7,377,350)
--   - Household count = 2,500
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: the 80% cut-off
-- ---------------------------------------------------------------------
WITH hh_spend AS (
    SELECT household_key,
           SUM(sales_value) AS sales
    FROM vw_transactions
    GROUP BY household_key
),
ranking AS (
    SELECT household_key,
           sales,
           ROW_NUMBER() OVER (ORDER BY sales DESC, household_key) AS position,
           COUNT(*)     OVER ()                                    AS total_hh,
           SUM(sales)   OVER ()                                    AS total_sales,
           -- Explicit ROWS: with the default frame (RANGE), households
           -- tied on sales would be summed together in the running total
           SUM(sales)   OVER (ORDER BY sales DESC, household_key
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                                   AS running_sales
    FROM hh_spend
)
SELECT position                                          AS households_needed,
       total_hh,
       ROUND(100.0 * position / total_hh, 1)             AS pct_households,
       ROUND(100.0 * running_sales / total_sales, 1)     AS pct_running_sales,
       ROUND(sales, 2)                                   AS spend_of_last_included
FROM ranking
WHERE running_sales >= 0.8 * total_sales
ORDER BY position
LIMIT 1;


-- ---------------------------------------------------------------------
-- Query B: decile curve (table for the report / chart)
-- ---------------------------------------------------------------------
WITH hh_spend AS (
    SELECT household_key,
           SUM(sales_value)          AS sales,
           COUNT(DISTINCT basket_id) AS visits
    FROM vw_transactions
    GROUP BY household_key
),
deciles AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY sales DESC, household_key) AS decile
    FROM hh_spend
)
SELECT decile,
       COUNT(*)                                                    AS households,
       ROUND(SUM(sales))                                           AS sales,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 1)      AS pct_sales,
       ROUND(100.0 * SUM(SUM(sales)) OVER (ORDER BY decile)
                   / SUM(SUM(sales)) OVER (), 1)                   AS pct_running_sales,
       ROUND(AVG(sales))                                           AS avg_spend_2y,
       ROUND(AVG(visits))                                          AS avg_visits,
       ROUND(SUM(sales) / SUM(visits), 2)                          AS avg_ticket
FROM deciles
GROUP BY decile
ORDER BY decile;
