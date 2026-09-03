-- ============================================================
-- 07_snowpipe.sql
-- Sets up Snowpipe with auto-ingest so new daily files landing
-- in Azure automatically trigger a load into RAW.MANDI_PRICES_RAW
-- -- no manual COPY INTO needed.
--
-- This is a multi-step handshake across Azure and Snowflake:
--   STEP 1 (here): create the notification integration
--   STEP 2 (Azure): create a Storage Queue + Event Grid
--                    subscription pointing at it, grant Snowflake
--                    access to the queue
--   STEP 3 (here): create the pipe itself
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA RAW;
USE WAREHOUSE MANDI_WH;

-- ------------------------------------------------------------
-- STEP 1: Notification integration
--
-- Replace <storage_account_name> and <queue_name> once you've
-- created the queue in Azure (Step 2 below). If you haven't
-- created the queue yet, do that first, then come back.
-- ------------------------------------------------------------
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS MANDI_NOTIFICATION_INT
    TYPE = QUEUE
    NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE
    ENABLED = TRUE
    AZURE_STORAGE_QUEUE_PRIMARY_URI = 'https://mandi.queue.core.windows.net/mandi-notification-queue'
    AZURE_TENANT_ID = '7ad4ff51-b4d9-4c04-b74f-b478b4dc95eb';

-- Reveals AZURE_CONSENT_URL and AZURE_MULTI_TENANT_APP_NAME for THIS
-- integration (may differ from the storage integration's app identity)

DESC NOTIFICATION INTEGRATION MANDI_NOTIFICATION_INT;


-- ------------------------------------------------------------
-- STEP 3: Create the pipe (run this AFTER completing the Azure
-- steps below and granting the notification integration's app
-- access to the queue)
-- ------------------------------------------------------------
CREATE OR REPLACE PIPE MANDI_RAW_PIPE
    AUTO_INGEST = TRUE
    INTEGRATION = 'MANDI_NOTIFICATION_INT'
    AS
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

SHOW PIPES;
SELECT SYSTEM$PIPE_STATUS('MANDI_RAW_PIPE');
-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
SHOW PIPES;
SELECT SYSTEM$PIPE_STATUS('MANDI_RAW_PIPE');




SELECT COUNT(*) FROM MANDI_PRICES_RAW WHERE arrival_date = '2026-09-03'; -- adjust day if needed
