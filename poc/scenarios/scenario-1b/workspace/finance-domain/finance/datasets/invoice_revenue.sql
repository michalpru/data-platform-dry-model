-- finance.invoice_revenue — LEGACY revenue view (finance domain repo)
-- ANSI SQL.
-- =========================================================================
-- Registry lifecycle: RETIRED. Superseded by finance.logic.recognize_revenue.
--
-- This view computes customer revenue from POSTED invoices and normalizes currency to USD,
-- but it has two defects that make it unsuitable for executive ARPAC:
--   * it SKIPS refunds and credit notes (shared.fact_refunds) — revenue is gross, not net;
--   * it uses invoice_date, with no revenue-recognition-timing rules.
--
-- It is deliberately left in the repository to demonstrate a failure mode: workspace
-- similarity search will surface it as "reusable", but it is NOT the authoritative definition.
-- =========================================================================
CREATE VIEW finance.invoice_revenue AS
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
