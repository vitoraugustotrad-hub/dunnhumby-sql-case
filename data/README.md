# Data

The CSV files are **not** included in this repository. The dataset is
distributed by dunnhumby under its own terms, so download it yourself and
place the files in this folder.

**Source:** Dunnhumby, "The Complete Journey", downloaded from Kaggle:
https://www.kaggle.com/datasets/frtgnn/dunnhumby-the-complete-journey

Download the full dataset (a free Kaggle account is required) and extract
the CSVs into this folder.

## Files used

| File | Rows | Used by |
|---|---|---|
| `transaction_data.csv` | 2,595,732 | all questions |
| `product.csv` | 92,353 | all questions (via `vw_transactions`) |
| `hh_demographic.csv` | 801 | q10 |
| `campaign_desc.csv` | 30 | q06, q07 |
| `campaign_table.csv` | 7,208 | q06, q07 |
| `coupon.csv` | 124,548 | q06, q07 |
| `coupon_redempt.csv` | 2,318 | q06, q07 |

`causal_data.csv` (~36M rows, in-store display and mailer flags) is part of
the dataset but not used by any question.

After placing the files here, follow "How to run" in the main README. The row
counts above are a quick check that the load worked.
