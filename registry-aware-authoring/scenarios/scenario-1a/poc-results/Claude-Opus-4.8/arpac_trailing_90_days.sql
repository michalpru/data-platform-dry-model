-- Snowflake SQL. Trailing-90-day ARPAC (Average Revenue per Active Customer).
--
-- ARPAC = net recognized revenue in USD (numerator)
--         / distinct count of active customers (denominator)
--
-- Reuse notes:
--   * Denominator reuses shared.dim_customers.is_active, the enterprise
--     active-customer definition already used by executive dashboards
--     ("placed >= 1 order in the last 12 months").
--   * Numerator reuses shared.fact_invoices (recognized revenue) and
--     shared.fact_refunds (returns), netted together.
--   * USD scope: the workspace has no FX rate dataset, so revenue is limited
--     to rows already denominated in USD (currency_code = 'USD'). See README.
CREATE OR REPLACE VIEW shared.metric_arpac_trailing_90_days AS
WITH params AS (
    -- Trailing-90-day window: [as_of_date - 90 days, as_of_date).
    SELECT
        CURRENT_DATE                    AS as_of_date,
        DATEADD(day, -90, CURRENT_DATE) AS window_start_date
),

-- Denominator: active customers, using the shared executive-dashboard
-- active-customer definition (dim_customers.is_active).
active_customer_denominator AS (
    SELECT customer_id
    FROM shared.dim_customers
    WHERE is_active = TRUE
),

-- Recognized invoice revenue (USD) inside the trailing-90-day window,
-- restricted to active customers only.
recognized_invoice_revenue AS (
    SELECT COALESCE(SUM(i.invoice_amount), 0) AS invoice_amount_usd
    FROM shared.fact_invoices i
    INNER JOIN active_customer_denominator a
        ON i.customer_id = a.customer_id
    CROSS JOIN params p
    WHERE i.invoice_status = 'POSTED'          -- recognized revenue only
      AND i.currency_code  = 'USD'
      AND i.invoice_date  >= p.window_start_date
      AND i.invoice_date  <  p.as_of_date
),

-- Approved refunds (USD) inside the trailing-90-day window, attributed to
-- active customers via the parent invoice.
approved_refunds AS (
    SELECT COALESCE(SUM(r.refund_amount), 0) AS refund_amount_usd
    FROM shared.fact_refunds r
    INNER JOIN shared.fact_invoices i
        ON r.invoice_id = i.invoice_id
    INNER JOIN active_customer_denominator a
        ON i.customer_id = a.customer_id
    CROSS JOIN params p
    WHERE r.refund_status = 'APPROVED'         -- approved returns only
      AND r.currency_code = 'USD'
      AND r.refund_date  >= p.window_start_date
      AND r.refund_date  <  p.as_of_date
),

active_customer_count AS (
    SELECT COUNT(*) AS active_customer_count
    FROM active_customer_denominator
)

SELECT
    p.as_of_date,
    p.window_start_date,
    (inv.invoice_amount_usd - ref.refund_amount_usd) AS net_recognized_revenue_usd,
    cnt.active_customer_count,
    (inv.invoice_amount_usd - ref.refund_amount_usd)
        / NULLIF(cnt.active_customer_count, 0)       AS arpac_trailing_90_days_usd
FROM params p
CROSS JOIN recognized_invoice_revenue inv
CROSS JOIN approved_refunds ref
CROSS JOIN active_customer_count cnt;
