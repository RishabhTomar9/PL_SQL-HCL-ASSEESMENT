-- Selecting Database
-- PHASE 1: Database & Schema Design

USE DATABASE sales_analytics;

-- Creating Schemas

CREATE OR REPLACE SCHEMA raw;
CREATE OR REPLACE SCHEMA staging;
CREATE OR REPLACE SCHEMA production;

-- Creating Tables
-- PHASE 2: RAW Tables (JSON landing)

CREATE OR REPLACE TABLE raw.customers (
    raw_data VARIANT
);

CREATE OR REPLACE TABLE raw.transactions (
    raw_data VARIANT
);

CREATE OR REPLACE TABLE raw.products (
    raw_data VARIANT
);

-- file format creation
-- PHASE 3: Load JSON Data

USE SCHEMA raw;

CREATE OR REPLACE FILE FORMAT json_fmt
TYPE = JSON;

-- Creating Stages

CREATE OR REPLACE STAGE data_stage
FILE_FORMAT = json_fmt;

-- Uploading Files In GUI Mode in Stage

-- Load data from stage

COPY INTO raw.customers
FROM @data_stage/customers.json
FILE_FORMAT = (FORMAT_NAME = json_fmt);

COPY INTO raw.transactions
FROM @data_stage/transactions.json
FILE_FORMAT = (FORMAT_NAME = json_fmt);

COPY INTO raw.products
FROM @data_stage/products.json
FILE_FORMAT = (FORMAT_NAME = json_fmt);

-- Verify raw load

SELECT * FROM raw.customers LIMIT 5;
SELECT * FROM raw.transactions LIMIT 5;
SELECT * FROM raw.products LIMIT 5;

-- PHASE 4: Transform → STAGING (Structured Tables)

-- Customers staging table

CREATE OR REPLACE TABLE staging.customers AS
SELECT
    raw_data:customer_id::INT      AS customer_id,
    raw_data:name::STRING          AS name,
    raw_data:email::STRING         AS email,
    raw_data:country::STRING       AS country,
    raw_data:created_at::TIMESTAMP AS created_at,
    CURRENT_TIMESTAMP()            AS loaded_at
FROM raw.customers;

-- Transactions staging table

CREATE OR REPLACE TABLE staging.transactions AS
SELECT
    raw_data:transaction_id::INT    AS transaction_id,
    raw_data:customer_id::INT       AS customer_id,
    raw_data:product_id::INT        AS product_id,
    raw_data:quantity::INT          AS quantity,
    raw_data:unit_price::DECIMAL(10,2) AS unit_price,
    raw_data:quantity::INT * raw_data:unit_price::DECIMAL(10,2)
                                     AS transaction_total,
    raw_data:transaction_date::DATE AS transaction_date,
    CURRENT_TIMESTAMP()             AS loaded_at
FROM raw.transactions;

-- Products staging table

CREATE OR REPLACE TABLE staging.products AS
SELECT
    raw_data:product_id::INT        AS product_id,
    raw_data:product_name::STRING   AS product_name,
    raw_data:category::STRING       AS category,
    raw_data:unit_price::DECIMAL(10,2) AS unit_price,
    raw_data:supplier_id::INT       AS supplier_id,
    CURRENT_TIMESTAMP()             AS loaded_at
FROM raw.products;


-- PHASE 5: Data Validation (Optional but important)

SELECT COUNT(*) FROM staging.customers;
SELECT COUNT(*) FROM staging.transactions;
SELECT COUNT(*) FROM staging.products;

SELECT COUNT(*) 
FROM staging.transactions
WHERE customer_id IS NULL;


-- PHASE 6: PRODUCTION Analytics Tables

-- Fact table – Daily Sales

CREATE OR REPLACE TABLE production.fact_sales AS
SELECT
    t.transaction_date AS sales_date,
    c.customer_id,
    p.product_id,
    p.category,
    c.country,
    SUM(t.quantity) AS quantity_sold,
    SUM(t.transaction_total) AS total_sales,
    COUNT(DISTINCT t.transaction_id) AS transaction_count
FROM staging.transactions t
JOIN staging.customers c ON t.customer_id = c.customer_id
JOIN staging.products p ON t.product_id = p.product_id
GROUP BY
    t.transaction_date,
    c.customer_id,
    p.product_id,
    p.category,
    c.country;


-- Dimension table – Customer Summary

CREATE OR REPLACE TABLE production.dim_customers AS
SELECT
    c.customer_id,
    c.name,
    c.email,
    c.country,
    c.created_at,
    COUNT(DISTINCT t.transaction_id) AS lifetime_transactions,
    SUM(t.transaction_total) AS lifetime_value,
    MAX(t.transaction_date) AS last_purchase_date
FROM staging.customers c
LEFT JOIN staging.transactions t
    ON c.customer_id = t.customer_id
GROUP BY
    c.customer_id,
    c.name,
    c.email,
    c.country,
    c.created_at;


-- PHASE 7: Analytics Views

 -- Daily Sales View

 CREATE OR REPLACE VIEW production.vw_daily_sales AS
SELECT
    sales_date,
    SUM(total_sales) AS daily_total,
    COUNT(DISTINCT customer_id) AS unique_customers,
    SUM(quantity_sold) AS units_sold,
    ROUND(
        SUM(total_sales) / NULLIF(COUNT(DISTINCT customer_id), 0),
        2
    ) AS avg_order_value
FROM production.fact_sales
GROUP BY sales_date
ORDER BY sales_date DESC;

-- Top Products View

CREATE OR REPLACE VIEW production.vw_top_products AS
SELECT
    product_id,
    category,
    SUM(quantity_sold) AS total_quantity,
    SUM(total_sales) AS total_sales
FROM production.fact_sales
GROUP BY product_id, category
ORDER BY total_sales DESC;

-- Customer Segmentation View (PRODUCTION)

CREATE OR REPLACE VIEW production.vw_customer_segments AS
SELECT
    CASE
        WHEN lifetime_value >= 10000 THEN 'VIP'
        WHEN lifetime_value >= 5000  THEN 'Gold'
        WHEN lifetime_value >= 1000  THEN 'Silver'
        ELSE 'Bronze'
    END AS segment,
    COUNT(*) AS customer_count,
    ROUND(SUM(lifetime_value), 2) AS segment_total_value,
    ROUND(AVG(lifetime_value), 2) AS avg_customer_value,
    MAX(last_purchase_date) AS most_recent_purchase
FROM production.dim_customers
WHERE lifetime_transactions > 0
GROUP BY segment
ORDER BY segment_total_value DESC;

-- Monitoring Table (PHASE 6 – Monitoring & Optimization)

CREATE OR REPLACE TABLE production.load_audit (
    load_timestamp TIMESTAMP,
    stage_name VARCHAR,
    table_name VARCHAR,
    row_count INT,
    success_indicator BOOLEAN
);

-- Final Verification

SELECT * FROM production.vw_daily_sales;
SELECT * FROM production.vw_top_products;
SELECT * FROM production.dim_customers;

 --Phase-8 Insert Load Metrics (for existing pipeline)

 INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'staging',
    'customers',
    (SELECT COUNT(*) FROM staging.customers),
    TRUE;

INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'staging',
    'transactions',
    (SELECT COUNT(*) FROM staging.transactions),
    TRUE;

INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'staging',
    'products',
    (SELECT COUNT(*) FROM staging.products),
    TRUE;

 -- After PRODUCTION load

 INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'production',
    'fact_sales',
    (SELECT COUNT(*) FROM production.fact_sales),
    TRUE;

INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'production',
    'dim_customers',
    (SELECT COUNT(*) FROM production.dim_customers),
    TRUE;

INSERT INTO production.load_audit
SELECT
    CURRENT_TIMESTAMP(),
    'production',
    'dim_customers',
    (SELECT COUNT(*) FROM production.dim_customers),
    TRUE;

-- Verify Monitoring Data

SELECT * 
FROM production.load_audit
ORDER BY load_timestamp DESC;


