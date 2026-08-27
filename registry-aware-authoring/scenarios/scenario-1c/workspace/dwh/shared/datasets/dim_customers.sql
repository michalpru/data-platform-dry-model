-- Snowflake SQL DDL
CREATE OR REPLACE TABLE shared.dim_customers (
    customer_id      NUMBER(38,0)  NOT NULL,
    customer_name    VARCHAR(200),
    is_active        BOOLEAN,       -- placed >= 1 order in the last 12 months
    last_order_date  DATE,
    PRIMARY KEY (customer_id)
);
