-- Snowflake SQL DDL
CREATE OR REPLACE TABLE shared.fact_refunds (
    refund_id       NUMBER(38,0)  NOT NULL,
    invoice_id      NUMBER(38,0)  NOT NULL,
    refund_date     DATE          NOT NULL,
    refund_status   VARCHAR(20)   NOT NULL,   -- e.g. 'APPROVED', 'PENDING', 'REJECTED'
    refund_amount   NUMBER(18,2)  NOT NULL,
    currency_code   VARCHAR(3)    NOT NULL,
    PRIMARY KEY (refund_id)
);
