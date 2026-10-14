-- =====================================================================
-- q01_rfm.sql
--
-- Business question: Who are the champion customers, who is at risk and
--                    who is already lost?
-- Why it matters:    Each segment calls for a different action: reward
--                    champions, re-engage those cooling off, stop spending
--                    budget on those who already left. It is the base of CRM.
-- Approach:
--   1. rfm_base:  per household, over the last 52 weeks (days 348-711):
--                 Recency (days since last purchase), Frequency (baskets)
--                 and Monetary (sales)
--   2. scores:    1-5 score on each dimension
--                 - R: fixed bands (<=3d, <=7d, <=14d, <=30d, >30d)
--                 - F and M: NTILE(5), quintiles across households
--   3. segment:   rules on R and on the average of F and M
--   4. Query A:   summary by segment; Query B: household-level list
-- Assumptions / filters:
--   - Base: vw_transactions; sales = SUM(sales_value)
--   - 52-week window instead of the full period: households joined the
--     panel gradually (weeks 1-16), which would penalize late joiners on
--     Frequency. By the last year everyone was active.
--   - Reference day = 711 (last day in the dataset)
--   - Households with no purchase in the window go straight to 'Lost'
--   - Why R does not use NTILE: recency has many ties and is concentrated
--     near zero; NTILE put households with the SAME value into different
--     scores. Fixed bands are also easier to explain to a stakeholder
--     ("hasn't bought in over 30 days").
--   - F and M have few ties; the household_key tie-breaker only makes
--     NTILE deterministic
-- Checks:
--   - Households across segments = 2,500
--   - Average recency should grow from Champions -> Hibernating
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: summary by segment
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT 711 AS ref_day, 711 - 363 AS start_day   -- 364 days = 52 weeks
),
rfm_base AS (
    SELECT t.household_key,
           p.ref_day - MAX(t.day)       AS recency_days,
           COUNT(DISTINCT t.basket_id)  AS frequency,
           SUM(t.sales_value)           AS monetary
    FROM vw_transactions t
    CROSS JOIN params p
    WHERE t.day BETWEEN p.start_day AND p.ref_day
    GROUP BY t.household_key, p.ref_day
),
scores AS (
    SELECT *,
           -- Recency: FIXED business bands, not NTILE. Half the households
           -- bought in the last ~4 days, so quintiles would cut at 1, 4, 9
           -- and 26 days and the same value would land in different
           -- quintiles (NTILE splits ties arbitrarily).
           CASE WHEN recency_days <=  3 THEN 5
                WHEN recency_days <=  7 THEN 4
                WHEN recency_days <= 14 THEN 3
                WHEN recency_days <= 30 THEN 2
                ELSE                         1 END                         AS r,
           NTILE(5) OVER (ORDER BY frequency, household_key) AS f,
           NTILE(5) OVER (ORDER BY monetary,  household_key) AS m
    FROM rfm_base
),
segments AS (
    SELECT household_key, recency_days, frequency, monetary, r, f, m,
           CASE
               WHEN r >= 4 AND (f + m) / 2.0 >= 4   THEN '1. Champions'
               WHEN r >= 3 AND (f + m) / 2.0 >= 3   THEN '2. Loyal'
               WHEN r >= 4                          THEN '3. Recent, low engagement'
               WHEN r <= 2 AND (f + m) / 2.0 >= 3   THEN '4. At risk'
               WHEN r =  3                          THEN '5. Needs attention'
               ELSE                                      '6. Hibernating'
           END AS segment
    FROM scores
    UNION ALL
    -- households in the dataset with no purchase in the window
    SELECT h.household_key, NULL, 0, 0, NULL, NULL, NULL, '7. Lost'
    FROM (SELECT DISTINCT household_key FROM transaction_data) h
    WHERE NOT EXISTS (SELECT 1 FROM rfm_base b WHERE b.household_key = h.household_key)
)
SELECT segment,
       COUNT(*)                                                         AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_households,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)     AS pct_sales,
       ROUND(AVG(recency_days))                                         AS avg_recency_days,
       ROUND(AVG(frequency))                                            AS avg_baskets_52w,
       ROUND(AVG(monetary))                                             AS avg_spend_52w
FROM segments
GROUP BY segment
ORDER BY segment;


-- ---------------------------------------------------------------------
-- Query B: household-level check (top 10 spenders currently at risk)
-- Useful for the CRM team: an actionable list, not just the aggregate.
-- ---------------------------------------------------------------------
WITH params AS (
    SELECT 711 AS ref_day, 711 - 363 AS start_day
),
rfm_base AS (
    SELECT t.household_key,
           p.ref_day - MAX(t.day)       AS recency_days,
           COUNT(DISTINCT t.basket_id)  AS frequency,
           SUM(t.sales_value)           AS monetary
    FROM vw_transactions t
    CROSS JOIN params p
    WHERE t.day BETWEEN p.start_day AND p.ref_day
    GROUP BY t.household_key, p.ref_day
),
scores AS (
    SELECT *,
           CASE WHEN recency_days <=  3 THEN 5
                WHEN recency_days <=  7 THEN 4
                WHEN recency_days <= 14 THEN 3
                WHEN recency_days <= 30 THEN 2
                ELSE                         1 END                         AS r,
           NTILE(5) OVER (ORDER BY frequency, household_key) AS f,
           NTILE(5) OVER (ORDER BY monetary,  household_key) AS m
    FROM rfm_base
)
SELECT household_key, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       r, f, m, CONCAT(r, f, m) AS rfm_code
FROM scores
WHERE r <= 2 AND (f + m) / 2.0 >= 3
ORDER BY monetary DESC
LIMIT 10;
