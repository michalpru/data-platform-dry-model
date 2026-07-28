-- shared.fact_invoices — issued invoices fact (central data warehouse: Snowflake)
-- Snowflake SQL DDL.
CREATE OR REPLACE TABLE shared.fact_invoices (
    invoice_id      NUMBER(38,0)  NOT NULL,
    customer_id     NUMBER(38,0)  NOT NULL,
    invoice_date    DATE          NOT NULL,
    invoice_status  VARCHAR(20)   NOT NULL,   -- e.g. 'POSTED', 'DRAFT', 'VOID'
    invoice_amount  NUMBER(18,2)  NOT NULL,
    currency_code   VARCHAR(3)    NOT NULL,   -- ISO 4217; invoices are NOT necessarily in USD
    PRIMARY KEY (invoice_id)
);
