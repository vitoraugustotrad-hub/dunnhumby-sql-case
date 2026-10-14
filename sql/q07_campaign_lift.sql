-- =====================================================================
-- q07_campaign_lift.sql
--
-- Business question: Do campaigns drive INCREMENTAL sales, or do they just
--                    discount purchases that would have happened anyway?
-- Why it matters:    Redemption rate (q06) measures adoption. If a customer
--                    redeemed a coupon for something they'd buy anyway, the
--                    campaign only cost margin. Budget decisions depend on
--                    lift, not redemption.
--
-- The problem: selection bias. Before the first campaign (days 113-223,
-- after panel onboarding), future recipients already spent 4.4x more than
-- households that never receive one (Query E). Query C shows the error of
-- comparing the two groups directly.
--
-- Method: difference-in-differences (DiD) + placebo test
--   For each campaign of duration D days:
--     pre-pre  = D days before the pre window   (placebo only)
--     pre      = D days before the start
--     during   = the campaign window
--   Treatment = households that received the campaign
--   Control   = households that receive campaigns at OTHER times, but were
--               not in any campaign during this one's pre-pre, pre or
--               during windows. Control v1 ("never received any campaign")
--               was dropped: it spent 5-7x less and had its own growth
--               trend.
--   Lift (relative DiD) = treatment % change / control % change
--   Placebo = same calculation between pre-pre and pre, where there was NO
--             campaign. If it is far from 0, the groups were already
--             diverging and the DiD alone is contaminated by that trend.
--   Adjusted lift = DiD - placebo. A HEURISTIC: it assumes the
--                   pre-existing divergence continues at the same pace.
--                   A sensitivity check, not a definitive estimate.
--
--   Why relative (%) and not absolute ($/day): treatment spends ~2x the
--   control. Assuming both would change by the same $/day without a
--   campaign is less plausible than assuming the same %.
--
-- Approach:
--   0. vw_lift_base: 1 row per household x campaign x group, with daily
--      spend TOTAL and on the CAMPAIGN'S PRODUCTS in each window
--   1. Query A: DiD + placebo + adjusted lift, total spend, by type
--   2. Query B: the same, only on the campaign's coupon products
--   3. Query C: the naive comparison (what NOT to do)
--   4. Query D: 95% confidence intervals (household-clustered SE)
--   5. Query E: spend gap between groups BEFORE any campaign
--
-- Assumptions / filters:
--   - Base: vw_transactions; metric = average daily spend per household;
--     a household with no purchase in a window counts as 0
--   - Only households already shopping before pre-pre (panel entry)
--   - Limitations: (1) campaigns overlap; (2) we don't know which coupons
--     each household received in TypeA; (3) DiD assumes parallel trends;
--     placebo point estimates are negative for all three types, but only
--     TypeC's is distinguishable from zero (Query D)
-- Checks:
--   - Treatment pairs = 7,208 (all sends from q06)
-- Run time: ~30 s (the view is recomputed on every query)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Helper view (run once)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_lift_base AS
WITH campaigns AS (
    SELECT campaign,
           description             AS campaign_type,
           start_day,
           end_day,
           end_day - start_day + 1 AS d
    FROM campaign_desc
),
first_purchase AS (
    SELECT household_key, MIN(day) AS first_day
    FROM vw_transactions
    GROUP BY household_key
),
sends AS (
    SELECT ct.household_key, cd.start_day, cd.end_day
    FROM campaign_table ct
    JOIN campaign_desc cd USING (campaign)
),
groups AS (
    SELECT household_key, campaign, 'treatment' AS grp
    FROM campaign_table
    UNION ALL
    SELECT h.household_key, c.campaign, 'control'
    FROM (SELECT DISTINCT household_key FROM campaign_table) h
    CROSS JOIN campaigns c
    WHERE NOT EXISTS (                      -- no campaign overlapping
        SELECT 1 FROM sends s                -- pre-pre, pre or during
        WHERE s.household_key = h.household_key
          AND s.start_day <= c.end_day
          AND s.end_day   >= c.start_day - 2 * c.d
    )
),
campaign_products AS (
    SELECT DISTINCT campaign, product_id FROM coupon
)
SELECT g.household_key, g.campaign, c.campaign_type, g.grp, c.d,
       -- total spend
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE t.day BETWEEN c.start_day - 2*c.d AND c.start_day - c.d - 1), 0) / c.d AS tot_prepre,
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE t.day BETWEEN c.start_day - c.d AND c.start_day - 1), 0) / c.d       AS tot_pre,
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE t.day BETWEEN c.start_day AND c.end_day), 0) / c.d                   AS tot_during,
       -- spend on this campaign's coupon products only
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE cp.product_id IS NOT NULL
             AND t.day BETWEEN c.start_day - 2*c.d AND c.start_day - c.d - 1), 0) / c.d AS cpn_prepre,
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE cp.product_id IS NOT NULL
             AND t.day BETWEEN c.start_day - c.d AND c.start_day - 1), 0) / c.d       AS cpn_pre,
       COALESCE(SUM(t.sales_value) FILTER (
           WHERE cp.product_id IS NOT NULL
             AND t.day BETWEEN c.start_day AND c.end_day), 0) / c.d                   AS cpn_during
FROM groups g
JOIN campaigns c        USING (campaign)
JOIN first_purchase fp  USING (household_key)
LEFT JOIN vw_transactions t
       ON t.household_key = g.household_key
      AND t.day BETWEEN c.start_day - 2 * c.d AND c.end_day
LEFT JOIN campaign_products cp
       ON cp.campaign   = g.campaign
      AND cp.product_id = t.product_id
WHERE fp.first_day < c.start_day - 2 * c.d
GROUP BY g.household_key, g.campaign, c.campaign_type, g.grp, c.d;


-- ---------------------------------------------------------------------
-- Query A: lift on TOTAL spend, with placebo
-- ---------------------------------------------------------------------
WITH m AS (
    SELECT campaign_type,
           COUNT(*)        FILTER (WHERE grp = 'treatment') AS n_treat,
           COUNT(*)        FILTER (WHERE grp = 'control')   AS n_ctrl,
           AVG(tot_prepre) FILTER (WHERE grp = 'treatment') AS t_pp,
           AVG(tot_pre)    FILTER (WHERE grp = 'treatment') AS t_p,
           AVG(tot_during) FILTER (WHERE grp = 'treatment') AS t_d,
           AVG(tot_prepre) FILTER (WHERE grp = 'control')   AS c_pp,
           AVG(tot_pre)    FILTER (WHERE grp = 'control')   AS c_p,
           AVG(tot_during) FILTER (WHERE grp = 'control')   AS c_d
    FROM vw_lift_base
    GROUP BY campaign_type
)
SELECT campaign_type, n_treat, n_ctrl,
       ROUND(t_p, 2)                                     AS treat_pre_per_day,
       ROUND(c_p, 2)                                     AS ctrl_pre_per_day,
       ROUND(100 * (t_d / t_p - 1), 1)                   AS treat_change_pct,
       ROUND(100 * (c_d / c_p - 1), 1)                   AS ctrl_change_pct,
       ROUND(100 * ((t_d / t_p) / (c_d / c_p) - 1), 1)   AS did_lift_pct,
       ROUND(100 * ((t_p / t_pp) / (c_p / c_pp) - 1), 1) AS placebo_pct,
       ROUND(100 * ((t_d / t_p) / (c_d / c_p) - 1)
           - 100 * ((t_p / t_pp) / (c_p / c_pp) - 1), 1) AS adjusted_lift_pct
FROM m
ORDER BY campaign_type;


-- ---------------------------------------------------------------------
-- Query B: lift only on the campaign's COUPON PRODUCTS
-- If there is an effect anywhere, it should show up here first.
-- ---------------------------------------------------------------------
WITH m AS (
    SELECT campaign_type,
           AVG(cpn_prepre) FILTER (WHERE grp = 'treatment') AS t_pp,
           AVG(cpn_pre)    FILTER (WHERE grp = 'treatment') AS t_p,
           AVG(cpn_during) FILTER (WHERE grp = 'treatment') AS t_d,
           AVG(cpn_prepre) FILTER (WHERE grp = 'control')   AS c_pp,
           AVG(cpn_pre)    FILTER (WHERE grp = 'control')   AS c_p,
           AVG(cpn_during) FILTER (WHERE grp = 'control')   AS c_d,
           AVG(cpn_pre / NULLIF(tot_pre, 0)) FILTER (WHERE grp = 'treatment')
                                                            AS coupon_share_treat
    FROM vw_lift_base
    GROUP BY campaign_type
)
SELECT campaign_type,
       ROUND(100 * coupon_share_treat, 1)                AS pct_spend_on_coupon_products,
       ROUND(t_p, 3)                                     AS treat_pre_per_day,
       ROUND(100 * (t_d / t_p - 1), 1)                   AS treat_change_pct,
       ROUND(100 * (c_d / c_p - 1), 1)                   AS ctrl_change_pct,
       ROUND(100 * ((t_d / t_p) / (c_d / c_p) - 1), 1)   AS did_lift_pct,
       ROUND(100 * ((t_p / t_pp) / (c_p / c_pp) - 1), 1) AS placebo_pct,
       ROUND(100 * ((t_d / t_p) / (c_d / c_p) - 1)
           - 100 * ((t_p / t_pp) / (c_p / c_pp) - 1), 1) AS adjusted_lift_pct
FROM m
ORDER BY campaign_type;


-- ---------------------------------------------------------------------
-- Query C: the NAIVE comparison (what not to do)
-- Treated vs never-targeted households, during the campaign only.
-- ---------------------------------------------------------------------
WITH campaigns AS (
    SELECT campaign, description AS campaign_type, start_day, end_day,
           end_day - start_day + 1 AS d
    FROM campaign_desc
),
never AS (
    SELECT DISTINCT household_key FROM vw_transactions t
    WHERE NOT EXISTS (SELECT 1 FROM campaign_table ct
                      WHERE ct.household_key = t.household_key)
),
during AS (
    SELECT c.campaign_type, 'received' AS grp, ct.household_key, c.campaign, c.d
    FROM campaign_table ct JOIN campaigns c USING (campaign)
    UNION ALL
    SELECT c.campaign_type, 'never received', n.household_key, c.campaign, c.d
    FROM never n CROSS JOIN campaigns c
),
spend AS (
    SELECT d.campaign_type, d.grp,
           COALESCE(SUM(t.sales_value), 0) / d.d AS spend_per_day
    FROM during d
    JOIN campaigns c USING (campaign)
    LEFT JOIN vw_transactions t
           ON t.household_key = d.household_key
          AND t.day BETWEEN c.start_day AND c.end_day
    GROUP BY d.campaign_type, d.grp, d.household_key, d.campaign, d.d
)
SELECT campaign_type,
       ROUND(AVG(spend_per_day) FILTER (WHERE grp = 'received'), 2)       AS received_per_day,
       ROUND(AVG(spend_per_day) FILTER (WHERE grp = 'never received'), 2) AS never_per_day,
       ROUND(100 * (AVG(spend_per_day) FILTER (WHERE grp = 'received')
                  / AVG(spend_per_day) FILTER (WHERE grp = 'never received') - 1))
                                                                          AS false_effect_pct
FROM spend
GROUP BY campaign_type
ORDER BY campaign_type;


-- ---------------------------------------------------------------------
-- Query D: uncertainty — 95% confidence intervals
--
-- Uses the LINEARIZED form of the estimators so each one is a plain mean
-- over (household, campaign) pairs:
--   DiD      ~ (t_during/t_pre - 1)    - (c_during/c_pre - 1)
--   placebo  ~ (t_pre/t_prepre - 1)    - (c_pre/c_prepre - 1)
--   adjusted ~ (t_during/t_pre - t_pre/t_prepre) - (same for control)
-- Point estimates are within ~1 pp of Query A (exact for small changes).
--
-- Standard errors are CLUSTERED BY HOUSEHOLD: the same household appears in
-- several campaigns (and controls appear in many), so pairs are not
-- independent. Cluster-robust SE of a mean = sqrt(sum_h S_h^2) / N, where
-- S_h is the sum of a household's deviations from the group mean and N the
-- number of pairs. CI = estimate +/- 1.96 x SE (treatment and control
-- variances added, as the groups are disjoint).
--
-- Caveats: the denominators (group means) are treated as fixed, and
-- shocks shared by all households in the same weeks are not modeled, so
-- these intervals are, if anything, too narrow.
-- ---------------------------------------------------------------------
WITH means AS (
    SELECT campaign_type, grp, COUNT(*) AS n_pairs,
           AVG(tot_prepre) AS pp, AVG(tot_pre) AS p
    FROM vw_lift_base
    GROUP BY campaign_type, grp
),
pair AS (
    SELECT b.household_key, b.campaign_type, b.grp,
           b.tot_during / m.p                     AS x_did,
           b.tot_pre    / m.pp                    AS x_plc,
           b.tot_during / m.p - b.tot_pre / m.pp  AS x_adj
    FROM vw_lift_base b
    JOIN means m USING (campaign_type, grp)
),
pair_dev AS (
    SELECT pair.*,
           x_did - AVG(x_did) OVER w AS e_did,
           x_plc - AVG(x_plc) OVER w AS e_plc,
           x_adj - AVG(x_adj) OVER w AS e_adj
    FROM pair
    WINDOW w AS (PARTITION BY campaign_type, grp)
),
clusters AS (
    SELECT campaign_type, grp, household_key,
           SUM(e_did) AS s_did, SUM(e_plc) AS s_plc, SUM(e_adj) AS s_adj
    FROM pair_dev
    GROUP BY campaign_type, grp, household_key
),
se AS (
    SELECT c.campaign_type, c.grp, COUNT(*) AS n_households,
           SQRT(SUM(s_did ^ 2)) / m.n_pairs AS se_did,
           SQRT(SUM(s_plc ^ 2)) / m.n_pairs AS se_plc,
           SQRT(SUM(s_adj ^ 2)) / m.n_pairs AS se_adj
    FROM clusters c
    JOIN means m USING (campaign_type, grp)
    GROUP BY c.campaign_type, c.grp, m.n_pairs
),
est AS (
    SELECT campaign_type, grp,
           AVG(x_did) - 1 AS did, AVG(x_plc) - 1 AS plc, AVG(x_adj) AS adj
    FROM pair
    GROUP BY campaign_type, grp
),
ci AS (
    SELECT t.campaign_type,
           st.n_households                                         AS hh_treat,
           sc.n_households                                         AS hh_ctrl,
           100 * (t.did - c.did)                                   AS did,
           196 * SQRT(st.se_did ^ 2 + sc.se_did ^ 2)               AS m_did,
           100 * (t.plc - c.plc)                                   AS plc,
           196 * SQRT(st.se_plc ^ 2 + sc.se_plc ^ 2)               AS m_plc,
           100 * (t.adj - c.adj)                                   AS adj,
           196 * SQRT(st.se_adj ^ 2 + sc.se_adj ^ 2)               AS m_adj
    FROM est t
    JOIN est c ON c.campaign_type = t.campaign_type AND c.grp = 'control'
    JOIN se st ON st.campaign_type = t.campaign_type AND st.grp = 'treatment'
    JOIN se sc ON sc.campaign_type = t.campaign_type AND sc.grp = 'control'
    WHERE t.grp = 'treatment'
)
SELECT campaign_type, hh_treat, hh_ctrl,
       ROUND(did, 1)                    AS did_pct,
       ROUND((did - m_did)::numeric, 1) AS did_ci_low,
       ROUND((did + m_did)::numeric, 1) AS did_ci_high,
       ROUND(plc, 1)                    AS placebo_pct,
       ROUND((plc - m_plc)::numeric, 1) AS placebo_ci_low,
       ROUND((plc + m_plc)::numeric, 1) AS placebo_ci_high,
       ROUND(adj, 1)                    AS adjusted_pct,
       ROUND((adj - m_adj)::numeric, 1) AS adjusted_ci_low,
       ROUND((adj + m_adj)::numeric, 1) AS adjusted_ci_high
FROM ci
ORDER BY campaign_type;
-- ROUND(double precision, int) doesn't exist in Postgres: SQRT returns
-- double, hence the ::numeric casts.


-- ---------------------------------------------------------------------
-- Query E: spend gap BEFORE any campaign
-- Days 113-223: after panel onboarding (~week 16) and before the first
-- campaign starts (day 224). Households that will ever receive a campaign
-- vs those that never do.
-- ---------------------------------------------------------------------
WITH spend AS (
    SELECT household_key, SUM(sales_value) AS sales
    FROM vw_transactions
    WHERE day BETWEEN 113 AND 223
    GROUP BY household_key
),
households AS (
    SELECT DISTINCT household_key,
           EXISTS (SELECT 1 FROM campaign_table ct
                   WHERE ct.household_key = t.household_key) AS ever_targeted
    FROM vw_transactions t
)
SELECT CASE WHEN h.ever_targeted THEN 'ever targeted' ELSE 'never targeted' END AS grp,
       COUNT(*)                                        AS households,
       ROUND(AVG(COALESCE(s.sales, 0)), 2)             AS avg_spend_days_113_223
FROM households h
LEFT JOIN spend s USING (household_key)
GROUP BY h.ever_targeted
ORDER BY grp;
