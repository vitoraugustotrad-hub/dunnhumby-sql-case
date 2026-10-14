-- =====================================================================
-- q06_campaign_redemption.sql
--
-- Business question: Which campaign type (TypeA / B / C) has the highest
--                    redemption rate? Which campaigns stand out?
-- Why it matters:    Shows where coupon budget gets a response. It is also
--                    the prerequisite for q07: redemption rate measures
--                    ADOPTION, not whether the campaign drove extra sales
--                    (lift).
-- Approach:
--   1. targets:     (household, campaign) pairs in campaign_table
--   2. redemptions: redemptions per (household, campaign) pair
--   3. LEFT JOIN targets -> redemptions: recipients who did not redeem get 0
--   4. Query A:     aggregate by type; Query B: ranking by campaign
--   5. Query C:     who redeems — is redemption concentrated in a few?
-- Assumptions / filters:
--   - Does not use vw_transactions: campaign/coupon tables don't have the
--     fuel and quantity issues
--   - "Redemption rate" = % of targeted households that redeemed >= 1
--     coupon of that campaign (denominator = who RECEIVED it, not who bought)
--   - Limitation: the dataset does not say WHICH coupons each household
--     received, only the campaign. Per the dataset guide, in TypeA each
--     household receives a personalized selection from the coupon pool; so
--     "coupons in the campaign" is not "coupons received per household".
-- Checks:
--   - All 2,318 redemptions are counted (verified in data quality: no
--     redemption by a household that didn't receive the campaign)
--   - 30 campaigns, 1,584 households received at least one campaign
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: redemption by campaign type
-- ---------------------------------------------------------------------
WITH campaign_coupons AS (
    SELECT campaign,
           COUNT(DISTINCT coupon_upc) AS coupons,
           COUNT(DISTINCT product_id) AS products
    FROM coupon
    GROUP BY campaign
),
redemptions AS (
    SELECT household_key, campaign, COUNT(*) AS n_redemptions
    FROM coupon_redempt
    GROUP BY household_key, campaign
),
targets AS (
    SELECT ct.household_key, ct.campaign, cd.description AS campaign_type,
           COALESCE(r.n_redemptions, 0) AS n_redemptions
    FROM campaign_table ct
    JOIN campaign_desc cd USING (campaign)
    LEFT JOIN redemptions r
           ON r.household_key = ct.household_key
          AND r.campaign      = ct.campaign
)
SELECT t.campaign_type,
       COUNT(DISTINCT t.campaign)                                      AS campaigns,
       ROUND(AVG(cd.end_day - cd.start_day + 1))                       AS avg_duration_days,
       ROUND(AVG(cc.coupons))                                          AS coupons_per_campaign,
       COUNT(*)                                                        AS sends,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT t.campaign))           AS sends_per_campaign,
       COUNT(*) FILTER (WHERE t.n_redemptions > 0)                     AS sends_with_redemption,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t.n_redemptions > 0) / COUNT(*), 1)
                                                                       AS redemption_rate_pct,
       SUM(t.n_redemptions)                                            AS redemptions,
       ROUND(SUM(t.n_redemptions)::numeric
             / NULLIF(COUNT(*) FILTER (WHERE t.n_redemptions > 0), 0), 1) AS coupons_per_redeemer
FROM targets t
JOIN campaign_desc    cd USING (campaign)
JOIN campaign_coupons cc USING (campaign)
GROUP BY t.campaign_type
ORDER BY t.campaign_type;
-- Note: AVG(duration) and AVG(coupons) here are weighted by send (each
-- row is a send). For the simple per-campaign values, see Query B.


-- ---------------------------------------------------------------------
-- Query B: campaign ranking
-- ---------------------------------------------------------------------
WITH campaign_coupons AS (
    SELECT campaign, COUNT(DISTINCT coupon_upc) AS coupons
    FROM coupon
    GROUP BY campaign
),
redemptions AS (
    SELECT household_key, campaign, COUNT(*) AS n_redemptions
    FROM coupon_redempt
    GROUP BY household_key, campaign
)
SELECT cd.campaign,
       cd.description                                                   AS campaign_type,
       cd.start_day, cd.end_day,
       cd.end_day - cd.start_day + 1                                    AS duration,
       cc.coupons,
       COUNT(ct.household_key)                                          AS sends,
       COUNT(r.household_key)                                           AS redeemers,
       ROUND(100.0 * COUNT(r.household_key) / NULLIF(COUNT(ct.household_key), 0), 1)
                                                                        AS redemption_rate_pct,
       COALESCE(SUM(r.n_redemptions), 0)                                AS redemptions,
       RANK() OVER (ORDER BY COUNT(r.household_key)::numeric
                             / NULLIF(COUNT(ct.household_key), 0) DESC) AS rank
FROM campaign_desc cd
JOIN campaign_coupons cc USING (campaign)
LEFT JOIN campaign_table ct USING (campaign)
LEFT JOIN redemptions r
       ON r.household_key = ct.household_key
      AND r.campaign      = ct.campaign
GROUP BY cd.campaign, cd.description, cd.start_day, cd.end_day, cc.coupons
ORDER BY rank, cd.campaign;
-- Caution: campaigns with few sends (e.g. campaign 3: 2 redeemers out of
-- 12 sends) rank high by chance. Flag or filter those under ~100 sends.


-- ---------------------------------------------------------------------
-- Query C: concentration — does redemption come from a few households?
-- ---------------------------------------------------------------------
WITH per_hh AS (
    SELECT ct.household_key,
           COUNT(DISTINCT ct.campaign)            AS campaigns_received,
           COUNT(DISTINCT r.campaign)             AS campaigns_redeemed,
           COUNT(r.coupon_upc)                    AS redemptions
    FROM campaign_table ct
    LEFT JOIN coupon_redempt r
           ON r.household_key = ct.household_key
          AND r.campaign      = ct.campaign
    GROUP BY ct.household_key
)
SELECT CASE
           WHEN redemptions = 0   THEN '1. never redeemed'
           WHEN redemptions <= 3  THEN '2. 1 to 3 redemptions'
           WHEN redemptions <= 10 THEN '3. 4 to 10'
           ELSE                        '4. more than 10'
       END                                                              AS profile,
       COUNT(*)                                                         AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_households,
       SUM(redemptions)                                                 AS redemptions,
       ROUND(100.0 * SUM(redemptions) / SUM(SUM(redemptions)) OVER (), 1) AS pct_redemptions,
       ROUND(AVG(campaigns_received), 1)                                AS avg_campaigns_received
FROM per_hh
GROUP BY 1
ORDER BY 1;
-- Caution: the LEFT JOIN multiplies rows (1 send x N redemptions), which
-- is why campaign counts use COUNT(DISTINCT ...).
