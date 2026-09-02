-- ============================================================
-- 03_raw_load.sql
-- Creates the raw landing table and loads all Mandi price CSVs
-- currently sitting in the Azure stage into it.
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA RAW;
USE WAREHOUSE MANDI_WH;


CREATE TABLE IF NOT EXISTS MANDI_PRICES_RAW (
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
                                                _loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                                                _file_name    VARCHAR
);

-- ------------------------------------------------------------
-- Load everything currently in the stage.
-- ON_ERROR = 'CONTINUE' skips bad rows instead of failing the
-- whole load -- useful while we're still trusting a new source.
-- ------------------------------------------------------------

COPY INTO MANDI_PRICES_RAW (
    state, district, market, commodity, variety, grade,
    arrival_date, min_price, max_price, modal_price, data_source, _file_name
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
        METADATA$FILENAME
    FROM @MANDI_RAW_STAGE
)
FILE_FORMAT = (TYPE = CSV, SKIP_HEADER = 1, FIELD_OPTIONALLY_ENCLOSED_BY = '"')
ON_ERROR = 'CONTINUE';

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------

SELECT COUNT(*) AS total_rows FROM MANDI_PRICES_RAW;

SELECT arrival_date, data_source, COUNT(*) AS record_count
FROM MANDI_PRICES_RAW
GROUP BY arrival_date, data_source
ORDER BY arrival_date;

SELECT COUNT(*) FROM MANDI_PRICES_RAW WHERE arrival_date = '2026-09-01';

SELECT * FROM MANDI_PRICES_RAW LIMIT 10;

