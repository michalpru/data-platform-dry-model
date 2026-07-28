-- shared.dim_customers — customer dimension (central data warehouse)
-- ANSI SQL DDL. See scenario-1a for the governance note on `is_active`.
CREATE TABLE shared.dim_customers (
    customer_id      BIGINT        NOT NULL,
    customer_name    VARCHAR(200),
    is_active        BOOLEAN,       -- placed >= 1 order in the last 12 months (NOT enterprise-grade)
    last_order_date  DATE,
    PRIMARY KEY (customer_id)
);
