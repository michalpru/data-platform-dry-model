-- shared.fact_refunds — refunds and credit notes fact (central data warehouse)
-- ANSI SQL DDL. The legacy invoice_revenue view in this scenario IGNORES this table — that is
-- exactly why reusing it silently overstates revenue.
CREATE TABLE shared.fact_refunds (
    refund_id       BIGINT        NOT NULL,
    invoice_id      BIGINT        NOT NULL,
    refund_date     DATE          NOT NULL,
    refund_status   VARCHAR(20)   NOT NULL,   -- e.g. 'APPROVED', 'PENDING', 'REJECTED'
    refund_amount   DECIMAL(18,2) NOT NULL,
    currency_code   VARCHAR(3)    NOT NULL,
    PRIMARY KEY (refund_id)
);
