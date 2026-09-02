-- ============================================================
-- 02_storage_integration.sql
-- Connects Snowflake to the Azure ADLS Gen2 'raw' container so
-- Snowflake can read the files uploaded by upload_to_adls.py.
--
-- This is a two-way handshake:
--   1. Run STEP 1 here in Snowflake to create the integration.
--   2. Go to Azure and grant the generated Snowflake identity
--      access to your storage account (see instructions below).
--   3. Come back and run STEP 2 to create the external stage.
-- ============================================================

USE DATABASE MANDI_DB;
USE SCHEMA RAW;

-- ------------------------------------------------------------
-- STEP 1: Create the storage integration
-- ------------------------------------------------------------

CREATE OR REPLACE STORAGE INTEGRATION MANDI_AZURE_INTEGRATION
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'AZURE'
    ENABLED = TRUE
    AZURE_TENANT_ID = '7ad4ff51-b4d9-4c04-b74f-b478b4dc95eb'
    STORAGE_ALLOWED_LOCATIONS = ('azure://mandi.blob.core.windows.net/raw/');

-- ------------------------------------------------------------
-- Run this next
-- ------------------------------------------------------------

DESC STORAGE INTEGRATION MANDI_AZURE_INTEGRATION;

-- ------------------------------------------------------------
-- STEP 2: Create the external stage
-- ------------------------------------------------------------

CREATE OR REPLACE STAGE MANDI_RAW_STAGE
    STORAGE_INTEGRATION = MANDI_AZURE_INTEGRATION
    URL = 'azure://mandi.blob.core.windows.net/raw/mandi/'
    FILE_FORMAT = (TYPE = CSV, SKIP_HEADER = 1, FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- Sanity check: list files Snowflake can see in the stage

LIST @MANDI_RAW_STAGE;