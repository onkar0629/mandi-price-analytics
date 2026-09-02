-- ============================================================
-- 01_setup.sql
-- Creates the warehouse, database, and schema layers for the
-- Mandi Price Analytics project.
-- ============================================================

-- Warehouse: compute engine that runs your queries.
-- X-Small is plenty for this project's data volume.
CREATE WAREHOUSE IF NOT EXISTS MANDI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60          -- suspend after 60s idle, saves credits
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Database: top-level container for everything in this project
CREATE DATABASE IF NOT EXISTS MANDI_DB;

USE DATABASE MANDI_DB;

-- Schemas: separate raw / staging / mart layers
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS MART;

-- Set context for the rest of today's session
USE WAREHOUSE MANDI_WH;
USE DATABASE MANDI_DB;
USE SCHEMA RAW;

-- Sanity check
SHOW SCHEMAS IN DATABASE MANDI_DB;