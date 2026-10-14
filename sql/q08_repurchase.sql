-- =====================================================================
-- q08_repurchase.sql
--
-- Business question: Which categories (commodities) do customers buy again
--                    within 30 days? Which are bought by many households but
--                    rarely repurchased?
-- Why it matters:    High-repurchase categories bring the customer back to
--                    the store (frequency anchors — the lever q01/q02/q05
--                    pointed to). Categories bought widely but rarely
--                    repurchased suggest customers replenishing elsewhere.
-- Approach:
--   1. occasions:  distinct days on which each household bought each
--                  commodity (2 items on the same day = 1 occasion)
--   2. next_buy:   LEAD() -> day of the next purchase of the same commodity
--                  by the same household
--   3. repurchase rate = % of occasions followed by another purchase within
--      <= 30 days. Occasions in the last 30 days (day > 681) are excluded:
--      there wasn't time to observe a repurchase (right censoring)
--   4. Query A: ranking (top and bottom); Query B: by department;
--      Query C: high penetration x low repurchase
-- Assumptions / filters:
--   - Base: vw_transactions
--   - Only commodities with >= 200 buying households and >= 1,000
--     evaluable occasions (avoids a 100% rate from 3 purchases)
--   - Penetration = % of the 2,500 households that bought the commodity
-- Checks:
--   - Rate between 0 and 100; daily staples (milk, bread) should be at the
--     top, durable/seasonal goods at the bottom
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: 30-day repurchase ranking
-- ---------------------------------------------------------------------
WITH occasions AS (
    SELECT DISTINCT household_key, department, commodity_desc, day
    FROM vw_transactions
),
next_buy AS (
    SELECT household_key, department, commodity_desc, day,
           LEAD(day) OVER (PARTITION BY household_key, commodity_desc
                           ORDER BY day) AS next_day
    FROM occasions
),
metrics AS (
    SELECT department, commodity_desc,
           COUNT(DISTINCT household_key)                                AS buyers,
           COUNT(*) FILTER (WHERE day <= 681)                           AS evaluable_occasions,
           COUNT(*) FILTER (WHERE day <= 681 AND next_day - day <= 30)  AS repurchases_30d,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY next_day - day)  AS median_interval
    FROM next_buy
    GROUP BY department, commodity_desc
),
ranking AS (
    SELECT *,
           100.0 * repurchases_30d / evaluable_occasions                      AS rate,
           RANK() OVER (ORDER BY 1.0 * repurchases_30d / evaluable_occasions DESC) AS pos_top,
           RANK() OVER (ORDER BY 1.0 * repurchases_30d / evaluable_occasions ASC)  AS pos_bottom
    FROM metrics
    WHERE buyers >= 200
      AND evaluable_occasions >= 1000
)
SELECT CASE WHEN pos_top <= 12 THEN 'top' ELSE 'bottom' END  AS grp,
       commodity_desc,
       department,
       buyers,
       ROUND(100.0 * buyers / 2500, 1)                        AS penetration_pct,
       ROUND(rate, 1)                                         AS repurchase_30d_pct,
       median_interval                                        AS median_interval_days
FROM ranking
WHERE pos_top <= 12 OR pos_bottom <= 12
ORDER BY rate DESC;


-- ---------------------------------------------------------------------
-- Query B: repurchase by department (weighted by occasion)
-- ---------------------------------------------------------------------
WITH occasions AS (
    SELECT DISTINCT household_key, department, commodity_desc, day
    FROM vw_transactions
),
next_buy AS (
    SELECT department, day,
           LEAD(day) OVER (PARTITION BY household_key, commodity_desc
                           ORDER BY day) AS next_day
    FROM occasions
)
SELECT department,
       COUNT(*) FILTER (WHERE day <= 681)                                      AS occasions,
       ROUND(100.0 * COUNT(*) FILTER (WHERE day <= 681 AND next_day - day <= 30)
                   / COUNT(*) FILTER (WHERE day <= 681), 1)                    AS repurchase_30d_pct
FROM next_buy
GROUP BY department
HAVING COUNT(*) FILTER (WHERE day <= 681) >= 5000
ORDER BY repurchase_30d_pct DESC;


-- ---------------------------------------------------------------------
-- Query C: opportunities — many households buy it, few replenish it here
-- Penetration >= 30% and repurchase below the median of eligible commodities
-- ---------------------------------------------------------------------
WITH occasions AS (
    SELECT DISTINCT household_key, department, commodity_desc, day
    FROM vw_transactions
),
next_buy AS (
    SELECT household_key, department, commodity_desc, day,
           LEAD(day) OVER (PARTITION BY household_key, commodity_desc
                           ORDER BY day) AS next_day
    FROM occasions
),
metrics AS (
    SELECT department, commodity_desc,
           COUNT(DISTINCT household_key)                                AS buyers,
           COUNT(*) FILTER (WHERE day <= 681)                           AS evaluable_occasions,
           100.0 * COUNT(*) FILTER (WHERE day <= 681 AND next_day - day <= 30)
                 / NULLIF(COUNT(*) FILTER (WHERE day <= 681), 0)        AS rate,
           COUNT(*)::numeric / COUNT(DISTINCT household_key)            AS occasions_per_buyer
    FROM next_buy
    GROUP BY department, commodity_desc
),
eligible AS (
    SELECT *
    FROM metrics
    WHERE buyers >= 200 AND evaluable_occasions >= 1000
),
-- PERCENTILE_CONT does not accept OVER() in Postgres (an ordered-set
-- aggregate cannot be a window function), so the median goes in a
-- one-row CTE
cutoff AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rate) AS median_rate
    FROM eligible
)
SELECT commodity_desc, department,
       ROUND(100.0 * buyers / 2500, 1)        AS penetration_pct,
       ROUND(rate, 1)                         AS repurchase_30d_pct,
       ROUND(cutoff.median_rate::numeric, 1)  AS overall_median_pct,
       ROUND(occasions_per_buyer, 1)          AS purchases_per_buyer_2y
FROM eligible
CROSS JOIN cutoff
WHERE buyers >= 0.30 * 2500
  AND rate < median_rate
ORDER BY penetration_pct DESC
LIMIT 15;
