# Retail Customer Analytics in Pure SQL — Dunnhumby "The Complete Journey"

Ten business questions for a grocery retailer answered only with SQL
(PostgreSQL), with the reasoning, checks and limitations for every query.

**Stakeholder:** Head of Loyalty & Marketing at a grocery chain, who wants to
know which customers matter, whether campaigns work, and where the risk is.

**Read the findings first:** [REPORT.md](REPORT.md) is written for the
stakeholder and contains no SQL.

---

## Headline findings

1. **Frequency drives customer value, not basket size.** Across spend deciles,
   visit frequency varies 17x while average ticket varies only 3x. RFM
   "Champions" (29% of households) generate 62% of sales.
2. **The risk is pausing, not churning.** Retention is flat at ~80% for two
   years; 92% of households paused at least once, and the typical pause lasts
   28 days.
3. **Campaigns get adoption, but incremental lift is not proven.** A naive
   comparison suggests +434% to +624%, but targeted households already spent
   4.4x more before any campaign. Raw difference-in-differences estimates
   are negative (−3% to −10%), and so is a placebo test on campaign-free
   windows. Subtracting the placebo (a heuristic correction) gives +1.5% to
   +3.4%, with 95% confidence intervals (household-clustered) that include
   zero for every campaign type.
4. **Assortment opportunities:** private-label share drops from ~24% to ~15%
   as income rises, even within the same department; "task" pairs such as
   pasta + pasta sauce co-occur ~10x more than chance.

---

## Questions and SQL techniques

| # | Question | Main techniques | File |
|---|---|---|---|
| 01 | Who are the champions, at-risk and lost customers? | `NTILE`, fixed-band scoring, chained CTEs, `UNION ALL` | [q01_rfm.sql](sql/q01_rfm.sql) |
| 02 | What % of households generates 80% of sales? | Running total with `SUM() OVER (ROWS ...)`, `NTILE(10)`, `SUM(SUM()) OVER ()` | [q02_pareto.sql](sql/q02_pareto.sql) |
| 03 | Do households keep shopping over time? | Cohort matrix with `FILTER` pivot, shifted self-join | [q03_retention.sql](sql/q03_retention.sql) |
| 04 | Who is away beyond their own pattern? | `LAG`, `PERCENTILE_CONT` (median / P90) | [q04_purchase_pauses.sql](sql/q04_purchase_pauses.sql) |
| 05 | How strong is the weekly habit? | Recursive CTE calendar, gaps-and-islands | [q05_weekly_streaks.sql](sql/q05_weekly_streaks.sql) |
| 06 | Which campaign type is redeemed most? | Multi-table joins, fan-out control with `COUNT(DISTINCT)`, `RANK` | [q06_campaign_redemption.sql](sql/q06_campaign_redemption.sql) |
| 07 | Do campaigns drive incremental sales? | Difference-in-differences, placebo test, household-clustered standard errors, `NOT EXISTS` anti-join | [q07_campaign_lift.sql](sql/q07_campaign_lift.sql) |
| 08 | Which categories are repurchased within 30 days? | `LEAD`, right censoring, ordered-set aggregates | [q08_repurchase.sql](sql/q08_repurchase.sql) |
| 09 | Which categories are bought together? | Self-join with `a < b`, support / confidence / lift, pruning | [q09_market_basket.sql](sql/q09_market_basket.sql) |
| 10 | Does private-label share fall with income? | Conditional aggregation, pooled vs averaged share, mix control | [q10_private_label.sql](sql/q10_private_label.sql) |

Every query file starts with a standard header: business question, why it
matters, approach, assumptions/filters, and how the result was checked.

---

## How to run

**Requirements:** PostgreSQL 13+ (developed on 16 and 18). Nothing else.

1. Download the dataset (see [data/README.md](data/README.md)) and put the CSVs in `data/`.
2. Create a database and run the files in order:

```bash
createdb dunnhumby
psql -d dunnhumby -f sql/00_create_tables.sql

# load the CSVs (from the repo root)
for t in hh_demographic product campaign_desc campaign_table coupon coupon_redempt transaction_data; do
  psql -d dunnhumby -c "\copy $t FROM 'data/$t.csv' WITH (FORMAT csv, HEADER)"
done

psql -d dunnhumby -f sql/01_data_quality.sql
psql -d dunnhumby -f sql/02_base_view.sql
psql -d dunnhumby -f sql/q01_rfm.sql   # ... through q10
```

In pgAdmin: run `00_create_tables.sql` in the Query Tool, then right-click
each table → *Import/Export Data* → Import, format `csv`, **Header on**.

Most queries run in a few seconds; `q07` and `q09` take ~30 s. The output of
every query is saved in [`results/`](results/).

---

## Data quality notes

All checks are in [`01_data_quality.sql`](sql/01_data_quality.sql), with
outputs in [`results/data_quality/`](results/data_quality/).

**Clean:** no nulls in key columns, no duplicate rows, no orphan records
(every product sold exists in the catalog; every redemption matches a valid
coupon, a household that received the campaign, and a date inside the
campaign window). Each basket belongs to exactly one household, day and
store, so `basket_id` can be used as a store visit.

**Issues and decisions:**

| Finding | Impact | Decision |
|---|---|---|
| Fuel and miscellaneous transactions (`KIOSK-GAS`, `MISC SALES TRAN`, commodity `COUPON/MISC ITEMS`) have `quantity` up to 89,638 and account for ~8.3% of sales | Distort any quantity or product-mix metric | Excluded in `vw_transactions` |
| Fuel is labeled under department `KIOSK-GAS` with commodity `COUPON/MISC ITEMS`, not commodity `FUEL` (6 rows) | Filtering on `commodity = 'FUEL'` would leave fuel in | Filter on department |
| 14,466 rows with `quantity = 0` and 18,879 with `sales_value = 0` | Break price averages and ratios | Excluded |
| Only 801 of 2,500 households have demographics; they account for 55.8% of sales | Income/age analyses are biased toward heavier shoppers | Stated in every demographic analysis |
| Gradual panel onboarding: 88 households shop in week 1, stabilizing at ~1,300/week around week 16; 99% of households make their first purchase by week 20 | "First purchase" is panel entry, not acquisition; early-week frequency is understated | RFM uses the last 52 weeks; no acquisition cohorts |
| Weeks 1 and 102 are incomplete (5 and 6 days) | Distort week-over-week series | Excluded from weekly series |
| No calendar dates (only `DAY` 1-711 and `WEEK_NO` 1-102) | Seasonality cannot be dated | Hypothesis: week 92 is Christmas (smoked meats 3.3x, baking 2.5x, Christmas seasonal 2.8x vs prior 10 weeks), so week ~40 is the previous Christmas. Not used as a fact |
| `sales_value` is what the retailer receives; discounts are stored as negative values | `sales_value - retail_disc - coupon_match_disc` gives the pre-discount shelf value, not the price paid | Sales = `SUM(sales_value)` throughout |
| 10 rows with positive `retail_disc` | Negligible | Noted only |
| `sales_value` has floating-point noise in the CSV (e.g. `1.3900000001`) | None after load | Stored as `numeric(10,2)` |
| Large IDs: `basket_id` reaches ~42 billion, `coupon_upc` has 11 digits | Import fails with `int` | Stored as `bigint` |

---

## Repository structure

```
├── README.md
├── REPORT.md                 findings for the stakeholder (no SQL)
├── data/README.md            how to get the data (CSVs are not committed)
├── sql/
│   ├── 00_create_tables.sql
│   ├── 01_data_quality.sql
│   ├── 02_base_view.sql      vw_transactions: the clean base for every question
│   └── q01 … q10
└── results/                  query outputs as CSV (q<NN>_<name>_<A|B|C>.csv)
    └── data_quality/
```

---

## Limitations

- **Observational data.** Every finding is a correlation. q07 shows how
  selection bias can create a large false effect, and why only a randomized
  holdout can measure campaign lift reliably.
- **Uncertainty is only quantified in q07.** Other analyses report point
  estimates; differences between small groups (e.g. the top income bands in
  q10) should be read with caution.
- **Curated panel.** Retention is unusually stable (~80% at every horizon),
  which suggests households were selected for staying in the panel. Churn
  metrics here measure pauses, not permanent loss.
- **Partial demographics.** 801 households, not a random sample.
- **Unknown coupon assignment.** For TypeA campaigns the dataset does not say
  which coupons each household received.
- **Arbitrary thresholds**, documented in each file: RFM bands, pause rules
  (3x median gap), 30-day repurchase window, minimum support in market basket.
