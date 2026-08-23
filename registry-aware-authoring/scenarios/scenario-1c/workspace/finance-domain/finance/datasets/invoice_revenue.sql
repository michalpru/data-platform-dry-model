-- Snowflake SQL
CREATE OR REPLACE VIEW finance.invoice_revenue AS
SELECT
    i.invoice_id,
    i.customer_id,
    CAST(i.invoice_date AS DATE)                    AS revenue_date,
    i.currency_code                                 AS source_currency,
    i.invoice_amount                                AS source_amount,
    ROUND(i.invoice_amount * fx.exchange_rate, 2)   AS invoice_revenue_usd
FROM shared.fact_invoices AS i
JOIN finance.dim_exchange_rates AS fx
  ON fx.from_currency = i.currency_code
 AND fx.to_currency   = 'USD'
 AND fx.rate_date     = CAST(i.invoice_date AS DATE)
WHERE i.invoice_status = 'POSTED';
