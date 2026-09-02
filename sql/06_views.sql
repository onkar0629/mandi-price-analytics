-- ============================================================
-- 06_views.sql
-- Analytical views on top of the mart layer -- these are what
-- Power BI connects to directly for each dashboard page.
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA MART;
USE WAREHOUSE MANDI_WH;

-- ------------------------------------------------------------
-- VW_PRICE_TRENDS
-- Average price per commodity per date -- powers the
-- "Overview" line chart of national price trends over time.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW VW_PRICE_TRENDS AS
SELECT
    c.commodity,
    f.date_key,
    ROUND(AVG(f.modal_price), 2) AS avg_modal_price,
    ROUND(AVG(f.min_price), 2)   AS avg_min_price,
    ROUND(AVG(f.max_price), 2)   AS avg_max_price,
    COUNT(*)                     AS observation_count
FROM FACT_MANDI_PRICES f
         JOIN DIM_COMMODITY c ON f.commodity_key = c.commodity_key
GROUP BY c.commodity, f.date_key;

-- ------------------------------------------------------------
-- VW_PRICE_VOLATILITY
-- Spread between max and min price per commodity/market/date --
-- powers the "which commodities are unstable right now" page.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW VW_PRICE_VOLATILITY AS
SELECT
    c.commodity,
    m.state,
    m.market,
    f.date_key,
    f.min_price,
    f.max_price,
    f.modal_price,
    (f.max_price - f.min_price) AS price_spread,
    ROUND((f.max_price - f.min_price) / NULLIF(f.modal_price, 0) * 100, 2)
                                AS spread_pct_of_modal
FROM FACT_MANDI_PRICES f
         JOIN DIM_COMMODITY c ON f.commodity_key = c.commodity_key
         JOIN DIM_MARKET m ON f.market_key = m.market_key;

-- ------------------------------------------------------------
-- VW_WOW_CHANGE
-- Week-over-week % change in average modal price per commodity.
-- Uses LAG() over a weekly aggregate.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW VW_WOW_CHANGE AS
WITH weekly AS (
    SELECT
        c.commodity,
        DATE_TRUNC('WEEK', f.date_key) AS week_start,
        ROUND(AVG(f.modal_price), 2)   AS avg_modal_price
    FROM FACT_MANDI_PRICES f
             JOIN DIM_COMMODITY c ON f.commodity_key = c.commodity_key
    GROUP BY c.commodity, DATE_TRUNC('WEEK', f.date_key)
)
SELECT
    commodity,
    week_start,
    avg_modal_price,
    LAG(avg_modal_price) OVER (
        PARTITION BY commodity ORDER BY week_start
        ) AS prev_week_price,
    ROUND(
            (avg_modal_price - LAG(avg_modal_price) OVER (
                PARTITION BY commodity ORDER BY week_start
                )) / NULLIF(LAG(avg_modal_price) OVER (
                PARTITION BY commodity ORDER BY week_start
                ), 0) * 100
        , 2) AS wow_pct_change
FROM weekly;

-- ------------------------------------------------------------
-- VW_STATE_COMPARISON
-- Average modal price by state and commodity -- powers the
-- choropleth map page.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW VW_STATE_COMPARISON AS
SELECT
    m.state,
    c.commodity,
    f.date_key,
    ROUND(AVG(f.modal_price), 2) AS avg_modal_price,
    COUNT(*)                     AS observation_count
FROM FACT_MANDI_PRICES f
         JOIN DIM_COMMODITY c ON f.commodity_key = c.commodity_key
         JOIN DIM_MARKET m ON f.market_key = m.market_key
GROUP BY m.state, c.commodity, f.date_key;

-- ------------------------------------------------------------
-- VW_TOP_VOLATILE_COMMODITIES
-- Ranking of commodities by average price spread -- a simple,
-- ready-to-chart "most unstable commodities today" view.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW VW_TOP_VOLATILE_COMMODITIES AS
SELECT
    commodity,
    date_key,
    ROUND(AVG(spread_pct_of_modal), 2) AS avg_spread_pct,
    RANK() OVER (
        PARTITION BY date_key ORDER BY AVG(spread_pct_of_modal) DESC
        ) AS volatility_rank
FROM VW_PRICE_VOLATILITY
GROUP BY commodity, date_key;

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
SELECT * FROM VW_PRICE_TRENDS ORDER BY date_key DESC LIMIT 10;
SELECT * FROM VW_WOW_CHANGE WHERE prev_week_price IS NOT NULL LIMIT 10;
SELECT * FROM VW_TOP_VOLATILE_COMMODITIES WHERE volatility_rank <= 5 ORDER BY date_key DESC;