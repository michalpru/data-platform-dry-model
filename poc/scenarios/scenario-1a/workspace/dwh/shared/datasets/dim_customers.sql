-- shared.dim_customers — customer dimension (central data warehouse)
-- ANSI SQL DDL.
--
-- GOVERNANCE WARNING: `is_active` here is a LOCAL warehouse-convenience flag. It marks any
-- customer who placed at least one order in the trailing 12 months. It is NOT the enterprise
-- "active customer" definition used for executive reporting (that is the certified 90-day
-- commercial-activity classification — see scenario-2 and the DRY Artifact Registry).
CREATE TABLE shared.dim_customers (
    customer_id      BIGINT        NOT NULL,
    customer_name    VARCHAR(200),
    is_active        BOOLEAN,       -- placed >= 1 order in the last 12 months (NOT enterprise-grade)
    last_order_date  DATE,
    PRIMARY KEY (customer_id)
);
