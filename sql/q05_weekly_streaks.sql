-- =====================================================================
-- q05_weekly_streaks.sql
--
-- Business question: How strong is the weekly shopping habit? Are
--                    customers with long streaks of consecutive weeks worth
--                    more? How many have the habit "on" right now?
-- Why it matters:    Habit is what q02 and q01 pointed to as the value
--                    driver (frequency > ticket). A streak of consecutive
--                    weeks is a simple habit metric, easy to track and to
--                    reward (e.g. "shop 4 weeks in a row and get X").
-- Approach:
--   1. calendar:  RECURSIVE CTE generates weeks 2..101
--   2. active:    weeks in which each household purchased
--   3. grid:      household x calendar (JOIN) + LEFT JOIN to active
--                 -> flags each week as purchase / no purchase
--   4. islands:   the gaps-and-islands trick:
--                 week - ROW_NUMBER() is constant inside a consecutive
--                 run of the same type
--   5. per_hh:    longest purchase streak, longest no-purchase streak,
--                 current streak (the one ending in week 101)
--   6. Query A:   value by longest-streak band
--      Query B:   distribution of the current streak
-- Assumptions / filters:
--   - Base: vw_transactions; weeks 1 and 102 excluded (incomplete)
--   - Weeks before a household's 1st purchase don't count as "no purchase"
--     (that is panel entry, not absence)
--   - On the recursion: in Postgres, generate_series(2, 101) does the same
--     and is more idiomatic. The recursive CTE is standard SQL (works in
--     Postgres, SQL Server, MySQL 8, SQLite) — that's why it's used here.
-- Checks:
--   - Calendar has 100 weeks
--   - For each household: purchase weeks + no-purchase weeks = weeks from
--     its 1st purchase to week 101
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: longest streak of purchase weeks x customer value
-- ---------------------------------------------------------------------
WITH RECURSIVE calendar AS (
    SELECT 2 AS week                        -- anchor
    UNION ALL
    SELECT week + 1                         -- recursive step
    FROM calendar
    WHERE week < 101                        -- stop condition
),
active AS (
    SELECT DISTINCT household_key, week_no AS week
    FROM vw_transactions
    WHERE week_no BETWEEN 2 AND 101
),
start_week AS (
    SELECT household_key, MIN(week) AS first_week
    FROM active
    GROUP BY household_key
),
grid AS (
    SELECT s.household_key,
           c.week,
           (a.household_key IS NOT NULL) AS purchased
    FROM start_week s
    JOIN calendar c    ON c.week >= s.first_week
    LEFT JOIN active a ON a.household_key = s.household_key
                      AND a.week          = c.week
),
islands AS (
    SELECT household_key, week, purchased,
           week - ROW_NUMBER() OVER (PARTITION BY household_key, purchased
                                     ORDER BY week) AS grp
    FROM grid
),
streaks AS (
    SELECT household_key, purchased,
           MIN(week)  AS first_wk,
           MAX(week)  AS last_wk,
           COUNT(*)   AS length
    FROM islands
    GROUP BY household_key, purchased, grp
),
per_hh AS (
    SELECT household_key,
           COALESCE(MAX(length) FILTER (WHERE purchased), 0)          AS longest_purchase_streak,
           COALESCE(MAX(length) FILTER (WHERE NOT purchased), 0)      AS longest_absence,
           COALESCE(MAX(length) FILTER (WHERE purchased AND last_wk = 101), 0)
                                                                      AS current_streak,
           SUM(length) FILTER (WHERE purchased)::numeric / SUM(length) AS pct_active_weeks
    FROM streaks
    GROUP BY household_key
),
spend AS (
    SELECT household_key, SUM(sales_value) AS sales
    FROM vw_transactions
    WHERE week_no BETWEEN 2 AND 101
    GROUP BY household_key
)
SELECT CASE
           WHEN longest_purchase_streak <  4 THEN '1. under 4 weeks'
           WHEN longest_purchase_streak < 13 THEN '2. 4 to 12'
           WHEN longest_purchase_streak < 27 THEN '3. 13 to 26'
           WHEN longest_purchase_streak < 53 THEN '4. 27 to 52'
           ELSE                                   '5. 53 or more'
       END                                                          AS longest_streak,
       COUNT(*)                                                     AS households,
       ROUND(100.0 * SUM(s.sales) / SUM(SUM(s.sales)) OVER (), 1)   AS pct_sales,
       ROUND(AVG(s.sales))                                          AS avg_spend,
       ROUND(100 * AVG(pct_active_weeks), 1)                        AS pct_active_weeks,
       ROUND(AVG(longest_absence), 1)                               AS avg_longest_absence
FROM per_hh
JOIN spend s USING (household_key)
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- Query B: CURRENT streak (ending in week 101)
-- How many households have the habit "on" right now?
-- ---------------------------------------------------------------------
WITH RECURSIVE calendar AS (
    SELECT 2 AS week
    UNION ALL
    SELECT week + 1 FROM calendar WHERE week < 101
),
active AS (
    SELECT DISTINCT household_key, week_no AS week
    FROM vw_transactions
    WHERE week_no BETWEEN 2 AND 101
),
start_week AS (
    SELECT household_key, MIN(week) AS first_week
    FROM active GROUP BY household_key
),
grid AS (
    SELECT s.household_key, c.week,
           (a.household_key IS NOT NULL) AS purchased
    FROM start_week s
    JOIN calendar c    ON c.week >= s.first_week
    LEFT JOIN active a ON a.household_key = s.household_key
                      AND a.week          = c.week
),
islands AS (
    SELECT household_key, week, purchased,
           week - ROW_NUMBER() OVER (PARTITION BY household_key, purchased
                                     ORDER BY week) AS grp
    FROM grid
),
final_streak AS (
    -- the run that contains week 101 (purchase or no purchase)
    SELECT household_key, purchased, COUNT(*) AS length
    FROM islands
    WHERE (household_key, purchased, grp) IN (
        SELECT household_key, purchased, grp FROM islands WHERE week = 101
    )
    GROUP BY household_key, purchased
)
SELECT CASE
           WHEN NOT purchased            THEN '0. no purchase in week 101'
           WHEN length =  1              THEN '1. last week only'
           WHEN length <  4              THEN '2. 2 to 3 weeks'
           WHEN length < 13              THEN '3. 4 to 12 weeks'
           ELSE                               '4. 13 weeks or more'
       END                                                AS current_streak,
       COUNT(*)                                           AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(AVG(length), 1)                              AS avg_weeks
FROM final_streak
GROUP BY 1
ORDER BY 1;
