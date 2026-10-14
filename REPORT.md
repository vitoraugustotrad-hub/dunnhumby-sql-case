# Customer Value, Retention and Campaign Effectiveness

**To:** Head of Loyalty & Marketing
**Data:** Dunnhumby "The Complete Journey": 2,500 households, 2 years
(102 weeks), 2.6 million line items
**Scope:** sales exclude fuel and miscellaneous transactions (~8% of raw
sales). See the README for all data decisions.

---

## Executive summary

1. **Customer value is driven by how often people shop, not how much they buy
   per trip.** The top 10% of households visit 17x more often than the bottom
   10%, but spend only 3x more per visit. Four independent analyses point to
   the same conclusion.
2. **Our customers don't leave; they pause.** Retention is stable at ~80% for
   two years, but about 10% of active customers skip each 4-week period.
   92% of households paused at least once, for a typical 28 days.
3. **Campaigns are redeemed, but we cannot show they increase sales.** The
   raw difference-in-differences estimates are negative (−3% to −10%), and
   so is a placebo test run where no campaign took place. Netting out that
   placebo gives +1.5% to +3.4%, with 95% confidence intervals that include
   zero for every campaign type. Measuring lift properly requires a
   randomized control group.
4. **Two assortment opportunities:** a premium private-label line for
   higher-income households, and cross-promotions built around shopping
   "tasks" (pasta + sauce, sliced cheese + deli meats).

---

## 1. Customer value

### Sales is concentrated, and frequency explains why

44.8% of households generate 80% of sales. The concentration is real but
moderate: this is not a classic 80/20.

| Spend decile | Share of sales | Visits in 2 years | Avg. ticket |
|---|---|---|---|
| Top 10% | 33.5% | 252 | $39.23 |
| 2nd | 18.7% | 170 | $32.38 |
| 5th | 7.9% | 102 | $22.76 |
| Bottom 10% | 0.7% | 15 | $13.58 |

Between the top and bottom deciles, **visit frequency varies 17x, ticket only
3x**. Valuable customers are the ones who come back often. *(q02)*

### Segmentation (RFM, last 52 weeks)

| Segment | Households | Share of sales | Days since last visit (avg) |
|---|---|---|---|
| Champions | 734 (29%) | 62.2% | 2 |
| Loyal | 482 (19%) | 18.3% | 5 |
| Recent, low engagement | 331 (13%) | 4.3% | 3 |
| **At risk** | **181 (7%)** | **7.8%** | **36** |
| Needs attention | 143 (6%) | 1.8% | 11 |
| Hibernating | 607 (24%) | 5.6% | 68 |
| Lost (no purchase in 52 weeks) | 22 (1%) | 0% | n/a |

The **At risk** segment is the priority: 181 households that bought as often
as Loyal customers (54 baskets a year) but haven't visited in 36 days on
average. A ranked list of these households is in `results/q01_rfm_B.csv`.
*(q01)*

### Habit is the strongest signal of value

Households whose longest run of consecutive shopping weeks exceeds a year
spend **$8,079** over the period, versus **$687** for those who never
exceeded 3 weeks, a **12x** difference. In any given week, half of households
(50.5%) don't shop. *(q05)*

> **Caveat:** heavy spenders naturally shop every week, so streaks may be a
> symptom of value rather than its cause. Only a test (e.g. rewarding a
> 4-week streak for a random group) would show whether building the habit
> raises spend.

### Frequency anchors

Milk, bread, soft drinks and cheese are in 94-97% of households and return
to the basket every 7-13 days (76-85% repurchased within 30 days). These are
the categories that bring customers back to the store; stock-outs or
uncompetitive prices here cost the most. *(q08)*

**Recommendations**
- Design loyalty rewards around **visit frequency** (points per visit,
  consecutive-week bonuses) rather than basket size.
- Protect availability and price perception on the frequency anchors.
- Target the 181 **At risk** households first; they are proven high-value
  customers.

---

## 2. Retention: pauses, not losses

Because nearly every household entered the panel in the first 20 weeks, we
measured retention period over period instead of by acquisition cohort.

- **Period-over-period retention is steady at ~89-90%.** Each 4-week period,
  ~200 households drop out and ~200 come back; the active base stays around
  1,980. *(q03)*
- **Cohort curves are flat at ~80%** at every horizon, with no decay over two
  years. Real customer cohorts decay, so the panel was likely selected for
  continuity. **Permanent churn cannot be measured in this data.** *(q03)*
- **Pausing is normal behavior:** 92% of households had at least one pause
  (an absence of more than 3x their usual gap and at least 14 days), 5.3 on
  average, with a median length of 28 days. All historical pauses ended with
  the customer returning. *(q04)*

Today, **339 households (13.6%) are in a pause** and 66 more are running late
versus their own pattern. Together they represent 10.9% of last-year sales.
*(q04)*

A fixed rule such as "60 days without buying" misses the point: household 232
usually shops **every day**, has been away **39 days**, and spent $3,700 last
year.

**Recommendations**
- Replace fixed inactivity rules with an **absence trigger relative to each
  customer's own rhythm**.
- Act in the "Late" window (the first 1-2 weeks past the customer's normal
  gap): the typical pause lasts 4 weeks, so the goal is to shorten it.

---

## 3. Campaign effectiveness

### Adoption

| Type | Campaigns | Coupons per campaign | Redemption rate |
|---|---|---|---|
| TypeA | 5 | 204 | 16.0% |
| TypeB | 19 | 15 | 7.9% |
| TypeC | 6 | 22 | 7.7% |

TypeA is redeemed twice as often, but it offers ~13x more coupons, so the
rates are not comparable. Redemption is highly concentrated: **3.5% of
targeted households make 44% of all redemptions**, and 73% never redeem.
Heavy redeemers also receive more campaigns (8.7 vs 3.9). *(q06)*

### Incremental effect

Redemption measures adoption, not extra sales. Before the first campaign
(days 113-223), households that would later be targeted already spent
**4.4x** more than households never targeted ($651 vs $148). Comparing the
two groups during campaigns therefore produces a **false effect of +434% to
+624%** *(q07, Queries C and E)*.

We used a difference-in-differences (DiD) design: each household's spend
during the campaign vs. the same number of days before, compared against
similar households with no campaign at that time. We then ran a **placebo
test**: the same calculation on two earlier windows with no campaign, where
the "effect" should be zero. 95% confidence intervals use standard errors
clustered by household.

| Type | DiD (raw) | Placebo (should be ~0) | DiD − placebo (heuristic) |
|---|---|---|---|
| TypeA | −3.0% [−9.5, +3.5] | −4.8% [−11.1, +1.4] | +1.9% [−0.9, +4.6] |
| TypeB | −4.4% [−11.7, +2.9] | −5.9% [−13.3, +1.5] | +1.5% [−1.0, +4.0] |
| TypeC | −9.6% [−19.1, 0.0] | −12.9% [−22.3, −3.6] | +3.4% [−1.2, +8.0] |

*Values from the linearized estimator in q07 Query D; the ratio form in
Query A differs by at most 1 percentage point.*

How to read it:

- **No campaign type shows a positive raw effect.** The raw DiD is negative
  for all three types; for TypeA and TypeB the interval includes zero.
- **The placebo is negative for all three types too**, which suggests
  targeted households were already growing more slowly than the control
  group (one possible cause: they are targeted at a spending peak and then
  revert to their average). This is only statistically clear for TypeC; for
  TypeA and TypeB the placebo interval includes zero.
- **Netting out the placebo gives +1.5% to +3.4%, and every interval
  includes zero.** This adjustment is a heuristic: it assumes the
  pre-existing gap keeps growing at the same pace. At most, it suggests
  that a large positive effect (above roughly +5% for TypeA and TypeB) is
  unlikely.
- **Looking only at the promoted products does not settle it.** For TypeA,
  whose coupons cover 40% of a household's spend, the net estimate is
  −1.2%. For TypeB and TypeC, promoted products are under 2% of spend, and
  the estimates swing from +6.9% to +17.3% with placebos down to −21.5%.
  That is too unstable to conclude anything. *(q07, Query B)*

The intervals are probably somewhat too narrow: they don't account for
shocks shared by all households in the same weeks, or for overlapping
campaigns.

**Recommendations**
- Do not use redemption rate as a success metric for campaign budget.
- Run future campaigns with a **randomized holdout** (e.g. 10% of eligible
  households not contacted). It is the only way to measure lift reliably.

---

## 4. Assortment opportunities

### Private label by income

| Income band | Households | Avg. spend | Private-label share |
|---|---|---|---|
| < $25K | 135 | $4,368 | 23.8% |
| $25-49K | 249 | $4,430 | 23.0% |
| $50-74K | 192 | $5,142 | 20.2% |
| $75-99K | 96 | $5,246 | 18.8% |
| $100-149K | 72 | $6,128 | 20.2% |
| $150K+ | 57 | $7,941 | 14.9% |

Share falls with income, and the drop holds **within the same department**
(Grocery 29.4% → 22.4%, Produce 16.3% → 9.7%, packaged meat 25.3% → 17.1%),
so it reflects preference, not only category mix. The highest-income group
spends the most but buys the least private label. *(q10)*

> Based on the 801 households with demographic data (55.8% of sales). The top
> bands have few households; the uptick at $100-149K is likely noise.

### Products bought together

The strongest associations are items from the same shopping task: cat food +
cat litter (16.8x more often than chance), laundry additives + detergent
(12.6x), pasta + pasta sauce (9.8x), sliced cheese + deli meats (9.2x). The
most frequent pairs (bread + milk, in 12% of baskets) have low lift: they are
simply popular. Direction matters for promotions: 44% of cat-litter baskets
include cat food, but only 20% of cat-food baskets include litter. *(q09)*

### Categories likely replenished elsewhere

Detergent, cooking oil, spices, sugar and toothpaste are bought by 65-76% of
households but repurchased less often than the median category. Buyers
purchased detergent here only ~5 times in two years, likely less than a
household uses. This suggests replenishment happens at other stores. The
data cannot confirm consumption, so this is a hypothesis to validate. *(q08)*

**Recommendations**
- Test a **premium private-label line** aimed at higher-income households.
- Build cross-promotions and adjacencies around **task pairs**, triggered by
  the item that "pulls" the other.
- Investigate share of wallet in household-care staples.

---

## Limitations

- All findings are correlations from observational data.
- The panel appears curated for continuity; churn results describe pauses.
- Demographics cover 801 of 2,500 households, not randomly selected.
- Coupon assignment per household is unknown for TypeA campaigns.
- Campaigns overlap in time, and the parallel-trends assumption of the
  campaign analysis is doubtful: placebo estimates are negative for every
  campaign type (clearly so for TypeC). The confidence intervals don't
  model week-level shocks and are likely somewhat too narrow.
- No calendar dates: seasonality can't be tied to specific months.
- Thresholds (RFM bands, pause rule, 30-day window, minimum support) are
  judgment calls, documented in each SQL file.
