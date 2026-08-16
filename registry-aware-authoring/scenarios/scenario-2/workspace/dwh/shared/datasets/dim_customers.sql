-- shared.datasets.dim_customers  (Snowflake SQL DDL)
-- Central customer dimension. IS_ACTIVE is an operational 12-month order-activity flag and is
-- NOT the certified executive active-customer definition (that is the Sales-owned
-- commercial_customer_status_90d). Retained here to reproduce the Scenario 1A failure mode.
CREATE OR REPLACE TABLE SHARED.DATASETS.DIM_CUSTOMERS (
    CUSTOMER_ID      NUMBER(38, 0) NOT NULL,
    CUSTOMER_NAME    VARCHAR,
    REGION_CODE      VARCHAR,
    LAST_ORDER_DATE  DATE,
    IS_ACTIVE        BOOLEAN,

    CONSTRAINT PK_DIM_CUSTOMERS
        PRIMARY KEY (CUSTOMER_ID)
);

COMMENT ON TABLE SHARED.DATASETS.DIM_CUSTOMERS IS
'Central customer dimension. IS_ACTIVE is an operational 12-month order-activity flag and is not the certified executive active-customer definition.';

COMMENT ON COLUMN SHARED.DATASETS.DIM_CUSTOMERS.IS_ACTIVE IS
'TRUE when the customer has placed at least one order during the previous 12 months. This column must not be used as the executive 90-day active-customer definition.';
