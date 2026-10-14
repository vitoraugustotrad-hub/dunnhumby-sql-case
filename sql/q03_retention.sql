-- =====================================================================
-- q03_retention.sql
--
-- Business question: Do households keep shopping over time? What is the
--                    period-over-period retention, and does it decay?
-- Why it matters:    Retention sustains the revenue of a repeat-purchase
--                    retailer; a slow, steady decline goes unnoticed in
--                    total sales until it becomes a problem.
--
-- WARNING — why this is NOT a classic acquisition cohort:
--   99% of households make their 1st purchase in weeks 1-20 (panel entry)
--   and only 18 join in the following 80 weeks. "First purchase" here is
--   the start of observation, not customer acquisition. Therefore:
--   - Query A: PANEL-ENTRY cohorts (periods 1-5), only to see whether the
--     retention curve is stable and similar across cohorts
--   - Query B: period-over-period retention (the useful business metric)
--
-- Approach:
--   1. activity:  4-week periods in which each household purchased
--                 (period p = weeks 4p-3 .. 4p; uses weeks 1-100 =
--                 25 complete periods, drops 101-102)
--   2. cohort:    first purchase period of each household
--   3. Query A:   % of the cohort active k periods later (pivot with FILTER)
--   4. Query B:   of those active in period p, how many are active in p+1
--                 (self-join of activity shifted by 1)
-- Assumptions / filters:
--   - Base: vw_transactions; "active" = at least 1 basket in the period
--   - Cohorts 6+ (18 households) are left out of Query A for size
-- Checks:
--   - Query A: k = 0 is 100% in every cohort (by definition)
--   - Sum of cohort sizes 1-5 = 2,482
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: cohort matrix (panel entry x periods since)
-- ---------------------------------------------------------------------
WITH activity AS (
    SELECT DISTINCT household_key,
           (week_no - 1) / 4 + 1 AS period             -- integer division
    FROM vw_transactions
    WHERE week_no <= 100
),
cohort AS (
    SELECT household_key,
           MIN(period) AS cohort_period
    FROM activity
    GROUP BY household_key
),
relative_activity AS (
    SELECT a.household_key,
           c.cohort_period,
           a.period - c.cohort_period AS k              -- periods since entry
    FROM activity a
    JOIN cohort c USING (household_key)
    WHERE c.cohort_period <= 5
)
SELECT cohort_period,
       COUNT(DISTINCT household_key)                                         AS cohort_size,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 0)  / COUNT(DISTINCT household_key), 1) AS k0,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 1)  / COUNT(DISTINCT household_key), 1) AS k1,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 2)  / COUNT(DISTINCT household_key), 1) AS k2,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 3)  / COUNT(DISTINCT household_key), 1) AS k3,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 6)  / COUNT(DISTINCT household_key), 1) AS k6,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 12) / COUNT(DISTINCT household_key), 1) AS k12,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 18) / COUNT(DISTINCT household_key), 1) AS k18,
       ROUND(100.0 * COUNT(*) FILTER (WHERE k = 20) / COUNT(DISTINCT household_key), 1) AS k20
FROM relative_activity
GROUP BY cohort_period
ORDER BY cohort_period;
-- Note: COUNT(*) FILTER (WHERE k = n) counts households because "activity"
-- has at most 1 row per household and period (DISTINCT above).


-- ---------------------------------------------------------------------
-- Query B: period-over-period retention (from period 6, after the ramp-up)
-- ---------------------------------------------------------------------
WITH activity AS (
    SELECT DISTINCT household_key,
           (week_no - 1) / 4 + 1 AS period
    FROM vw_transactions
    WHERE week_no <= 100
),
first_purchase AS (
    SELECT household_key, MIN(period) AS first_period
    FROM activity
    GROUP BY household_key
),
transition AS (
    SELECT a.period,
           COUNT(*)                                        AS active,
           COUNT(nxt.household_key)                        AS retained_next_period
    FROM activity a
    LEFT JOIN activity nxt
           ON nxt.household_key = a.household_key
          AND nxt.period        = a.period + 1
    WHERE a.period BETWEEN 6 AND 24                        -- 25 has no "next"
    GROUP BY a.period
),
reactivated AS (
    -- active in p, NOT active in p-1, and had purchased before
    SELECT a.period, COUNT(*) AS reactivated
    FROM activity a
    JOIN first_purchase fp USING (household_key)
    WHERE a.period BETWEEN 6 AND 24
      AND fp.first_period < a.period
      AND NOT EXISTS (SELECT 1 FROM activity prev
                      WHERE prev.household_key = a.household_key
                        AND prev.period        = a.period - 1)
    GROUP BY a.period
)
SELECT t.period,
       t.active,
       t.retained_next_period,
       ROUND(100.0 * t.retained_next_period / t.active, 1)  AS pct_retention,
       t.active - t.retained_next_period                    AS leave_next_period,
       COALESCE(r.reactivated, 0)                           AS returned_this_period
FROM transition t
LEFT JOIN reactivated r USING (period)
ORDER BY t.period;
