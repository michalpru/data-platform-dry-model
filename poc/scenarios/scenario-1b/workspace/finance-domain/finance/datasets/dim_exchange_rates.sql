-- finance.dim_exchange_rates — currency conversion rates (finance domain repo)
-- ANSI SQL DDL. Consumed by normalize_currency and the legacy invoice_revenue view.
CREATE TABLE finance.dim_exchange_rates (
    from_currency   VARCHAR(3)    NOT NULL,
    to_currency     VARCHAR(3)    NOT NULL,
    rate_date       DATE          NOT NULL,
    exchange_rate   DECIMAL(18,8) NOT NULL,
    PRIMARY KEY (from_currency, to_currency, rate_date)
);
