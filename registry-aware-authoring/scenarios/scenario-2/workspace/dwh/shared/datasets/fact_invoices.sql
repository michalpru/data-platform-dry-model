-- shared.datasets.fact_invoices  (Snowflake SQL DDL)
-- Issued invoice facts. Invoice dates and posted amounts do not by themselves constitute the
-- certified recognized-revenue definition.
CREATE OR REPLACE TABLE SHARED.DATASETS.FACT_INVOICES (
    INVOICE_ID       NUMBER(38, 0) NOT NULL,
    CUSTOMER_ID      NUMBER(38, 0) NOT NULL,
    CONTRACT_ID      NUMBER(38, 0),
    PRODUCT_ID       NUMBER(38, 0),

    INVOICE_DATE     DATE NOT NULL,
    POSTED_DATE      DATE,
    INVOICE_STATUS   VARCHAR NOT NULL,

    INVOICE_AMOUNT   NUMBER(18, 2) NOT NULL,
    CURRENCY_CODE    VARCHAR(3) NOT NULL,

    SOURCE_SYSTEM    VARCHAR NOT NULL DEFAULT 'ERP',

    CONSTRAINT PK_FACT_INVOICES
        PRIMARY KEY (INVOICE_ID)
);

COMMENT ON TABLE SHARED.DATASETS.FACT_INVOICES IS
'Issued invoice facts. Invoice dates and posted amounts do not by themselves constitute the certified recognized-revenue definition.';
