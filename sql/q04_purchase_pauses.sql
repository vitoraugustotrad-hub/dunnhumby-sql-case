-- =====================================================================
-- q04_purchase_pauses.sql
--
-- Business question: Which households are currently away well beyond
--                    their own purchase pattern? How often does it happen?
-- Why it matters:    q03 showed the problem is not permanent loss but
--                    intermittent absence (~10% skip each period). A single
--                    rule ("30 days without buying") fails both ways: 30 days
--                    is normal for a monthly shopper and alarming for someone
--                    who comes 3x a week. The trigger has to be relative to
--                    EACH household's pattern.
-- Approach:
--   1. visits:    distinct purchase days per household (2 baskets on the
--                 same day = 1 visit)
--   2. gaps:      days since the previous visit with LAG()
--   3. pattern:   median and 90th percentile of each household's gap
--                 (PERCENTILE_CONT — median because the mean is pulled
--                 by vacations and outliers)
--   4. status:    compares the CURRENT gap (711 - last visit) with the
--                 household's own pattern
--   5. Query B:   actionable list (highest spend first)
--   6. Query C:   history — how many pauses happened in 2 years and how
--                 long they lasted
-- Assumptions / filters:
--   - Base: vw_transactions; reference day = 711
--   - Only households with >= 10 gaps (stable pattern); the rest are
--     'Not enough history'
--   - Rules (adjustable):
--       'Paused'  : current gap > 3x median AND > P90 AND >= 14 days
--       'Late'    : current gap > P90 AND >= 7 days
--       'Normal'  : everything else
--     The day floors avoid alerts for daily shoppers (median = 1 day)
-- Checks:
--   - Households across statuses = 2,500
--   - Most should be 'Normal' (consistent with ~90% retention)
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: current status of households
-- ---------------------------------------------------------------------
WITH visits AS (
    SELECT DISTINCT household_key, day
    FROM vw_transactions
),
gaps AS (
    SELECT household_key, day,
           day - LAG(day) OVER (PARTITION BY household_key ORDER BY day) AS gap
    FROM visits
),
pattern AS (
    SELECT household_key,
           COUNT(gap)                                            AS n_gaps,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap)      AS median_gap,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap)      AS p90_gap,
           711 - MAX(day)                                        AS current_gap
    FROM gaps
    GROUP BY household_key
),
spend AS (
    SELECT household_key, SUM(sales_value) AS sales_52w
    FROM vw_transactions
    WHERE day >= 348
    GROUP BY household_key
),
status AS (
    SELECT p.*,
           COALESCE(s.sales_52w, 0) AS sales_52w,
           CASE
               WHEN p.n_gaps < 10                               THEN '4. Not enough history'
               WHEN p.current_gap > 3 * p.median_gap
                AND p.current_gap > p.p90_gap
                AND p.current_gap >= 14                         THEN '1. Paused'
               WHEN p.current_gap > p.p90_gap
                AND p.current_gap >= 7                          THEN '2. Late'
               ELSE                                                  '3. Normal'
           END AS status
    FROM pattern p
    LEFT JOIN spend s USING (household_key)
)
SELECT status,
       COUNT(*)                                                           AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                 AS pct_households,
       ROUND(SUM(sales_52w))                                              AS sales_52w,
       ROUND(100.0 * SUM(sales_52w) / SUM(SUM(sales_52w)) OVER (), 1)     AS pct_sales,
       ROUND(AVG(median_gap)::numeric, 1)                                 AS avg_median_gap,
       ROUND(AVG(current_gap))                                            AS avg_current_gap
FROM status
GROUP BY status
ORDER BY status;


-- ---------------------------------------------------------------------
-- Query B: actionable list — households 'Paused', highest spend first
-- ---------------------------------------------------------------------
WITH visits AS (
    SELECT DISTINCT household_key, day FROM vw_transactions
),
gaps AS (
    SELECT household_key, day,
           day - LAG(day) OVER (PARTITION BY household_key ORDER BY day) AS gap
    FROM visits
),
pattern AS (
    SELECT household_key,
           COUNT(gap)                                            AS n_gaps,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap)      AS median_gap,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap)      AS p90_gap,
           711 - MAX(day)                                        AS current_gap
    FROM gaps
    GROUP BY household_key
)
SELECT p.household_key,
       p.median_gap                                      AS usually_returns_in_days,
       ROUND(p.p90_gap::numeric, 1)                      AS p90_gap,   -- PERCENTILE_CONT returns float
       p.current_gap                                     AS days_without_buying,
       ROUND((p.current_gap / p.median_gap)::numeric, 1) AS times_normal,
       ROUND(SUM(t.sales_value))                         AS sales_52w
FROM pattern p
JOIN vw_transactions t
  ON t.household_key = p.household_key AND t.day >= 348
WHERE p.n_gaps >= 10
  AND p.current_gap > 3 * p.median_gap
  AND p.current_gap > p.p90_gap
  AND p.current_gap >= 14
GROUP BY p.household_key, p.median_gap, p.p90_gap, p.current_gap
ORDER BY sales_52w DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- Query C: pause history over 2 years
-- A historical "pause" = gap > 3x the household's median and >= 14 days.
-- Shows whether pausing is common behavior (and whether people come back).
-- ---------------------------------------------------------------------
WITH visits AS (
    SELECT DISTINCT household_key, day FROM vw_transactions
),
gaps AS (
    SELECT household_key, day,
           day - LAG(day) OVER (PARTITION BY household_key ORDER BY day) AS gap
    FROM visits
),
pattern AS (
    SELECT household_key,
           COUNT(gap)                                        AS n_gaps,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap)  AS median_gap
    FROM gaps
    GROUP BY household_key
),
pauses AS (
    SELECT g.household_key, g.gap
    FROM gaps g
    JOIN pattern p USING (household_key)
    WHERE p.n_gaps >= 10
      AND g.gap > 3 * p.median_gap
      AND g.gap >= 14
)
SELECT
    (SELECT COUNT(*) FROM pattern WHERE n_gaps >= 10)               AS households_evaluated,
    COUNT(DISTINCT household_key)                                   AS households_with_pause,
    ROUND(100.0 * COUNT(DISTINCT household_key)
          / (SELECT COUNT(*) FROM pattern WHERE n_gaps >= 10), 1)   AS pct_with_pause,
    COUNT(*)                                                        AS completed_pauses,
    ROUND(COUNT(*)::numeric / NULLIF(COUNT(DISTINCT household_key), 0), 1)
                                                                    AS pauses_per_household,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap)                AS median_duration_days
FROM pauses;
-- "completed": every LAG gap ends at a visit, i.e. the household came
-- back. Ongoing pauses are in Query A.
