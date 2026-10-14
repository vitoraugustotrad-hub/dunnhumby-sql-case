-- =====================================================================
-- q09_market_basket.sql
--
-- Business question: Which categories are bought TOGETHER in the same
--                    basket beyond what chance would explain?
-- Why it matters:    Guides store layout (place nearby), cross-promotions
--                    ("buy A, get a discount on B") and recommendations. But
--                    only pairs with LIFT > 1 are real associations; frequent
--                    pairs may just be popular items landing together by
--                    chance.
-- Metrics (for pair A, B):
--   support(A,B)    = % of baskets containing A and B
--   confidence(A→B) = % of baskets with A that also contain B
--   lift(A,B)       = support(A,B) / (support(A) x support(B))
--                     1 = independent; > 1 = together more than chance;
--                     < 1 = avoid each other
-- Approach:
--   1. basket_commodity: distinct (basket, commodity) pairs
--   2. freq: support of each commodity; keeps only those in >= 1% of
--      baskets (shrinks the self-join from ~14.5M to a few million pairs)
--   3. pairs: self-join on the same basket with a.commodity < b.commodity
--      (< rather than <>: each pair appears once, no (A,B) and (B,A)
--       duplicates, and no (A,A) pair)
--   4. Query A: highest lift; Query B: most frequent pairs (contrast);
--      Query C: rules for one anchor (e.g. BEEF)
-- Assumptions / filters:
--   - Base: vw_transactions; unit = basket (basket_id)
--   - Commodity level (~300); product level would give pairs too rare
--   - Minimum pair support = 0.5% of baskets (~1,250 baskets) in Query A,
--     so lift isn't inflated by rare pairs
-- Checks:
--   - Total baskets = 250,965 (baskets in the view with at least 1 item)
--   - Popular pairs with no logical link (milk + soft drinks) have low
--     lift; complementary pairs (pasta + sauce) have high lift
--   - Known bias: variation in basket size pushes the lift of almost every
--     pair above 1 (see Query B)
-- Run time: ~20-40 s on a local Postgres
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query A: pairs with the highest lift (association beyond chance)
-- ---------------------------------------------------------------------
WITH basket_commodity AS (
    SELECT DISTINCT basket_id, commodity_desc
    FROM vw_transactions
),
total AS (
    SELECT COUNT(DISTINCT basket_id)::numeric AS n_baskets
    FROM basket_commodity
),
freq AS (
    SELECT commodity_desc, COUNT(*) AS n
    FROM basket_commodity
    GROUP BY commodity_desc
    HAVING COUNT(*) >= 0.01 * (SELECT n_baskets FROM total)
),
pairs AS (
    SELECT a.commodity_desc AS item_a,
           b.commodity_desc AS item_b,
           COUNT(*)         AS n_ab
    FROM basket_commodity a
    JOIN basket_commodity b
      ON b.basket_id      = a.basket_id
     AND a.commodity_desc < b.commodity_desc
    WHERE a.commodity_desc IN (SELECT commodity_desc FROM freq)
      AND b.commodity_desc IN (SELECT commodity_desc FROM freq)
    GROUP BY a.commodity_desc, b.commodity_desc
)
SELECT p.item_a,
       p.item_b,
       p.n_ab                                                   AS baskets_together,
       ROUND(100 * p.n_ab / t.n_baskets, 2)                     AS support_pct,
       ROUND(100.0 * p.n_ab / fa.n, 1)                          AS conf_a_to_b_pct,
       ROUND(100.0 * p.n_ab / fb.n, 1)                          AS conf_b_to_a_pct,
       ROUND((p.n_ab * t.n_baskets) / (fa.n::numeric * fb.n), 2) AS lift
FROM pairs p
CROSS JOIN total t
JOIN freq fa ON fa.commodity_desc = p.item_a
JOIN freq fb ON fb.commodity_desc = p.item_b
WHERE p.n_ab >= 0.005 * t.n_baskets
ORDER BY lift DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- Query B: MOST FREQUENT pairs — contrast with Query A
-- The most common pairs have low lift (1.3-2.1): popular items that land
-- together in almost any large shop. Note: almost EVERY pair has lift > 1
-- in this dataset because large baskets contain many items — basket size
-- inflates lift. So lift ~2 here is not "strong"; the Query A pairs
-- (6-17) are the ones that stand out.
-- ---------------------------------------------------------------------
WITH basket_commodity AS (
    SELECT DISTINCT basket_id, commodity_desc FROM vw_transactions
),
total AS (
    SELECT COUNT(DISTINCT basket_id)::numeric AS n_baskets FROM basket_commodity
),
freq AS (
    SELECT commodity_desc, COUNT(*) AS n
    FROM basket_commodity
    GROUP BY commodity_desc
    HAVING COUNT(*) >= 0.01 * (SELECT n_baskets FROM total)
),
pairs AS (
    SELECT a.commodity_desc AS item_a, b.commodity_desc AS item_b, COUNT(*) AS n_ab
    FROM basket_commodity a
    JOIN basket_commodity b
      ON b.basket_id = a.basket_id AND a.commodity_desc < b.commodity_desc
    WHERE a.commodity_desc IN (SELECT commodity_desc FROM freq)
      AND b.commodity_desc IN (SELECT commodity_desc FROM freq)
    GROUP BY a.commodity_desc, b.commodity_desc
)
SELECT p.item_a, p.item_b,
       p.n_ab                                                    AS baskets_together,
       ROUND(100 * p.n_ab / t.n_baskets, 2)                      AS support_pct,
       ROUND((p.n_ab * t.n_baskets) / (fa.n::numeric * fb.n), 2) AS lift
FROM pairs p
CROSS JOIN total t
JOIN freq fa ON fa.commodity_desc = p.item_a
JOIN freq fb ON fb.commodity_desc = p.item_b
ORDER BY p.n_ab DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- Query C: rules for an anchor category (swap 'BEEF' freely)
-- "Customers who buy beef, what else do they buy?" — sorted by confidence,
-- only rules with lift > 1.2
-- ---------------------------------------------------------------------
WITH basket_commodity AS (
    SELECT DISTINCT basket_id, commodity_desc FROM vw_transactions
),
total AS (
    SELECT COUNT(DISTINCT basket_id)::numeric AS n_baskets FROM basket_commodity
),
freq AS (
    SELECT commodity_desc, COUNT(*) AS n
    FROM basket_commodity
    GROUP BY commodity_desc
),
anchor_baskets AS (
    SELECT basket_id FROM basket_commodity WHERE commodity_desc = 'BEEF'
),
together AS (
    SELECT c.commodity_desc, COUNT(*) AS n_ab
    FROM basket_commodity c
    JOIN anchor_baskets a USING (basket_id)
    WHERE c.commodity_desc <> 'BEEF'
    GROUP BY c.commodity_desc
)
SELECT 'BEEF'                                                      AS if_buys,
       j.commodity_desc                                            AS also_buys,
       j.n_ab                                                      AS baskets_together,
       ROUND(100.0 * j.n_ab / fa.n, 1)                             AS confidence_pct,
       ROUND(100.0 * fb.n / t.n_baskets, 1)                        AS base_rate_pct,  -- % of all baskets
       ROUND((j.n_ab * t.n_baskets) / (fa.n::numeric * fb.n), 2)   AS lift
FROM together j
CROSS JOIN total t
JOIN freq fa ON fa.commodity_desc = 'BEEF'
JOIN freq fb ON fb.commodity_desc = j.commodity_desc
WHERE j.n_ab >= 500
  AND (j.n_ab * t.n_baskets) / (fa.n::numeric * fb.n) > 1.2
ORDER BY confidence_pct DESC
LIMIT 12;
