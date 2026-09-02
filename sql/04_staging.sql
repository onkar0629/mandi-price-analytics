-- ============================================================
-- 04_staging.sql
-- Cleans and types the raw data:
--   - casts arrival_date to a real DATE
--   - casts prices to NUMBER
--   - trims/standardizes text fields
--   - separates invalid rows into a rejects table instead of
--     silently dropping them
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA STAGING;
USE WAREHOUSE MANDI_WH;

-- ------------------------------------------------------------
-- Rejects table: rows that failed validation, kept for visibility
-- rather than silently discarded. Good talking point in interviews:
-- "bad data is quarantined and inspectable, not just dropped."
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS MANDI_PRICES_REJECTS (
                                                    state         VARCHAR,
                                                    district      VARCHAR,
                                                    market        VARCHAR,
                                                    commodity     VARCHAR,
                                                    variety       VARCHAR,
                                                    grade         VARCHAR,
                                                    arrival_date  VARCHAR,
                                                    min_price     VARCHAR,
                                                    max_price     VARCHAR,
                                                    modal_price   VARCHAR,
                                                    data_source   VARCHAR,
                                                    reject_reason VARCHAR,
                                                    _rejected_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ------------------------------------------------------------
-- Insert invalid rows into rejects, tagging *why* they failed
-- ------------------------------------------------------------
INSERT INTO MANDI_PRICES_REJECTS
(state, district, market, commodity, variety, grade, arrival_date,
 min_price, max_price, modal_price, data_source, reject_reason)
SELECT
    state, district, market, commodity, variety, grade, arrival_date,
    min_price, max_price, modal_price, data_source,
    CASE
        WHEN TRY_TO_DATE(arrival_date, 'YYYY-MM-DD') IS NULL
            AND TRY_TO_DATE(arrival_date, 'DD/MM/YYYY') IS NULL
            THEN 'invalid arrival_date'
        WHEN TRY_TO_NUMBER(modal_price) IS NULL THEN 'invalid modal_price'
        WHEN state IS NULL OR TRIM(state) = '' THEN 'missing state'
        WHEN commodity IS NULL OR TRIM(commodity) = '' THEN 'missing commodity'
        ELSE 'unknown'
        END AS reject_reason
FROM MANDI_DB.RAW.MANDI_PRICES_RAW
WHERE
    (TRY_TO_DATE(arrival_date, 'YYYY-MM-DD') IS NULL
        AND TRY_TO_DATE(arrival_date, 'DD/MM/YYYY') IS NULL)
   OR TRY_TO_NUMBER(modal_price) IS NULL
   OR state IS NULL OR TRIM(state) = ''
   OR commodity IS NULL OR TRIM(commodity) = '';

-- ------------------------------------------------------------
-- Clean, typed staging table -- built from only the valid rows
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE MANDI_PRICES_CLEAN AS
SELECT DISTINCT
    UPPER(TRIM(state))      AS state,
    UPPER(TRIM(district))   AS district,
    UPPER(TRIM(market))     AS market,
    UPPER(TRIM(commodity))  AS commodity,
    UPPER(TRIM(variety))    AS variety,
    UPPER(TRIM(grade))      AS grade,
    COALESCE(
            TRY_TO_DATE(arrival_date, 'YYYY-MM-DD'),
            TRY_TO_DATE(arrival_date, 'DD/MM/YYYY')
    )                        AS arrival_date,
    TRY_TO_NUMBER(min_price)   AS min_price,
    TRY_TO_NUMBER(max_price)   AS max_price,
    TRY_TO_NUMBER(modal_price) AS modal_price,
    data_source
FROM MANDI_DB.RAW.MANDI_PRICES_RAW
WHERE
    (TRY_TO_DATE(arrival_date, 'YYYY-MM-DD') IS NOT NULL
        OR TRY_TO_DATE(arrival_date, 'DD/MM/YYYY') IS NOT NULL)
  AND TRY_TO_NUMBER(modal_price) IS NOT NULL
  AND state IS NOT NULL AND TRIM(state) != ''
  AND commodity IS NOT NULL AND TRIM(commodity) != '';

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
SELECT COUNT(*) AS clean_rows FROM MANDI_PRICES_CLEAN;
SELECT COUNT(*) AS rejected_rows FROM MANDI_PRICES_REJECTS;

SELECT reject_reason, COUNT(*) AS n
FROM MANDI_PRICES_REJECTS
GROUP BY reject_reason
ORDER BY n DESC;

SELECT arrival_date, data_source, COUNT(*) AS record_count
FROM MANDI_PRICES_CLEAN
GROUP BY arrival_date, data_source
ORDER BY arrival_date;

SELECT * FROM MANDI_PRICES_CLEAN LIMIT 10;