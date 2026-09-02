-- ============================================================
-- 05_mart.sql
-- Builds the star schema: DIM_COMMODITY, DIM_MARKET, DIM_DATE,
-- and FACT_MANDI_PRICES. This is what Power BI connects to.
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA MART;
USE WAREHOUSE MANDI_WH;

-- ------------------------------------------------------------
-- DIM_COMMODITY: one row per distinct commodity/variety/grade
-- combination, with a surrogate key for joining
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_COMMODITY AS
SELECT
    ROW_NUMBER() OVER (ORDER BY commodity, variety, grade) AS commodity_key,
    commodity,
    variety,
    grade
FROM (
         SELECT DISTINCT commodity, variety, grade
         FROM MANDI_DB.STAGING.MANDI_PRICES_CLEAN
     );

-- ------------------------------------------------------------
-- DIM_MARKET: one row per distinct state/district/market
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_MARKET AS
SELECT
    ROW_NUMBER() OVER (ORDER BY state, district, market) AS market_key,
    state,
    district,
    market
FROM (
         SELECT DISTINCT state, district, market
         FROM MANDI_DB.STAGING.MANDI_PRICES_CLEAN
     );

-- ------------------------------------------------------------
-- DIM_DATE: a proper calendar table, generated for a wide range
-- so it works regardless of how far back/forward your data goes.
-- Power BI needs this marked as a "Date Table" for time
-- intelligence functions (WoW, MoM, YoY) to work.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_DATE AS
          WITH date_spine AS (
              SELECT DATEADD(DAY, SEQ4(), '2024-01-01'::DATE) AS date_value
              FROM TABLE(GENERATOR(ROWCOUNT => 1500))  -- ~4 years of dates
              )
SELECT
    date_value                                   AS date_key,
    YEAR(date_value)                             AS year,
    MONTH(date_value)                            AS month,
    DAY(date_value)                              AS day,
    DAYNAME(date_value)                          AS day_name,
    MONTHNAME(date_value)                        AS month_name,
    WEEK(date_value)                             AS week_of_year,
    QUARTER(date_value)                          AS quarter
FROM date_spine;

-- ------------------------------------------------------------
-- FACT_MANDI_PRICES: the grain here is one row per
-- market + commodity + date (i.e. one price observation)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_MANDI_PRICES AS
SELECT
    c.commodity_key,
    m.market_key,
    stg.arrival_date        AS date_key,
    stg.min_price,
    stg.max_price,
    stg.modal_price,
    stg.data_source
FROM MANDI_DB.STAGING.MANDI_PRICES_CLEAN stg
         JOIN DIM_COMMODITY c
              ON stg.commodity = c.commodity
                  AND stg.variety = c.variety
                  AND stg.grade = c.grade
         JOIN DIM_MARKET m
              ON stg.state = m.state
                  AND stg.district = m.district
                  AND stg.market = m.market;

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
SELECT COUNT(*) AS fact_rows FROM FACT_MANDI_PRICES;
SELECT COUNT(*) AS commodity_count FROM DIM_COMMODITY;
SELECT COUNT(*) AS market_count FROM DIM_MARKET;
SELECT COUNT(*) AS date_count FROM DIM_DATE;

-- Confirm every fact row successfully joined to its dimensions
-- (row counts should match between staging and fact)
SELECT
    (SELECT COUNT(*) FROM MANDI_DB.STAGING.MANDI_PRICES_CLEAN) AS staging_rows,
    (SELECT COUNT(*) FROM FACT_MANDI_PRICES) AS fact_rows;