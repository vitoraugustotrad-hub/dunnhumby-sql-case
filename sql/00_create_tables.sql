-- =====================================================================
-- 00_create_tables.sql — Dunnhumby "The Complete Journey" (PostgreSQL)
--
-- Column order follows each CSV header EXACTLY: the import matches
-- columns by position, not by name.
-- =====================================================================

DROP VIEW  IF EXISTS vw_lift_base, vw_transactions;
DROP TABLE IF EXISTS transaction_data, hh_demographic, product,
                     campaign_desc, campaign_table, coupon, coupon_redempt;

-- household_key,BASKET_ID,DAY,PRODUCT_ID,QUANTITY,SALES_VALUE,STORE_ID,
-- RETAIL_DISC,TRANS_TIME,WEEK_NO,COUPON_DISC,COUPON_MATCH_DISC
CREATE TABLE transaction_data (
    household_key      int,
    basket_id          bigint,          -- up to ~42 billion: does not fit in int
    day                int,
    product_id         bigint,
    quantity           int,             -- reaches ~90k (fuel)
    sales_value        numeric(10,2),   -- CSV has float noise (1.3900000001); rounded to 2 decimals
    store_id           int,
    retail_disc        numeric(10,2),
    trans_time         int,             -- HHMM, e.g. 1631
    week_no            int,
    coupon_disc        numeric(10,2),
    coupon_match_disc  numeric(10,2)
);

-- AGE_DESC,MARITAL_STATUS_CODE,INCOME_DESC,HOMEOWNER_DESC,HH_COMP_DESC,
-- HOUSEHOLD_SIZE_DESC,KID_CATEGORY_DESC,household_key
CREATE TABLE hh_demographic (
    age_desc             text,
    marital_status_code  text,
    income_desc          text,
    homeowner_desc       text,
    hh_comp_desc         text,
    household_size_desc  text,          -- contains "5+"
    kid_category_desc    text,          -- contains "3+" and "None/Unknown"
    household_key        int PRIMARY KEY
);

-- PRODUCT_ID,MANUFACTURER,DEPARTMENT,BRAND,COMMODITY_DESC,
-- SUB_COMMODITY_DESC,CURR_SIZE_OF_PRODUCT
CREATE TABLE product (
    product_id            bigint PRIMARY KEY,
    manufacturer          int,
    department            text,
    brand                 text,          -- 'National' / 'Private'
    commodity_desc        text,
    sub_commodity_desc    text,
    curr_size_of_product  text           -- many blanks (" ")
);

-- DESCRIPTION,CAMPAIGN,START_DAY,END_DAY
CREATE TABLE campaign_desc (
    description  text,                   -- TypeA / TypeB / TypeC
    campaign     int PRIMARY KEY,
    start_day    int,
    end_day      int
);

-- DESCRIPTION,household_key,CAMPAIGN
CREATE TABLE campaign_table (
    description    text,
    household_key  int,
    campaign       int
);

-- COUPON_UPC,PRODUCT_ID,CAMPAIGN
CREATE TABLE coupon (
    coupon_upc  bigint,                  -- 11 digits: needs bigint
    product_id  bigint,
    campaign    int
);

-- household_key,DAY,COUPON_UPC,CAMPAIGN
CREATE TABLE coupon_redempt (
    household_key  int,
    day            int,
    coupon_upc     bigint,
    campaign       int
);

-- Load each CSV afterwards, e.g. with psql:
--   \copy transaction_data FROM 'data/transaction_data.csv' WITH (FORMAT csv, HEADER)
-- or in pgAdmin: right-click table > Import/Export Data > Import, csv, Header ON.
-- causal_data (36M rows) is not used by any question and is not created here.
