-- shared.datasets.fact_refunds  (Snowflake SQL DDL)
-- Approved refunds and credit notes associated with customer billing activity.
CREATE OR REPLACE TABLE SHARED.DATASETS.FACT_REFUNDS (
    REFUND_ID        NUMBER(38, 0) NOT NULL,
    INVOICE_ID       NUMBER(38, 0),
    CUSTOMER_ID      NUMBER(38, 0) NOT NULL,
    CONTRACT_ID      NUMBER(38, 0),
    PRODUCT_ID       NUMBER(38, 0),

    REFUND_DATE      DATE NOT NULL,
    APPROVED_DATE    DATE,
    REFUND_STATUS    VARCHAR NOT NULL,

    REFUND_AMOUNT    NUMBER(18, 2) NOT NULL,
    CURRENCY_CODE    VARCHAR(3) NOT NULL,

    REFUND_TYPE      VARCHAR NOT NULL DEFAULT 'REFUND',
    SOURCE_SYSTEM    VARCHAR NOT NULL DEFAULT 'ERP',

    CONSTRAINT PK_FACT_REFUNDS
        PRIMARY KEY (REFUND_ID)
);

COMMENT ON TABLE SHARED.DATASETS.FACT_REFUNDS IS
'Approved refunds and credit notes associated with customer billing activity.';
