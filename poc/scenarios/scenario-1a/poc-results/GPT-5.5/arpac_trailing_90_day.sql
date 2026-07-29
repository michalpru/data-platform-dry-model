-- Trailing-90-day ARPAC (Average Revenue per Active Customer) for executive reporting.
--
-- Reused local workspace artifacts:
-- - shared.dim_customers: source of the active-customer definition. The local DDL defines
--   is_active as customers that placed >= 1 order in the last 12 months, which aligns this
--   metric with the active-customer definition already available to executive dashboards.
-- - shared.fact_invoices: source of recognized gross revenue. POSTED invoices are treated
--   as recognized revenue events.
-- - shared.fact_refunds: source of revenue offsets. APPROVED refunds are subtracted from
--   recognized invoice revenue.
--
-- Currency handling:
-- The local workspace has currency_code columns but no FX-rate or currency-conversion
-- artifact, so this implementation reports USD ARPAC by including only USD invoice and
-- refund events.

CREATE OR REPLACE VIEW shared.arpac_trailing_90_day AS
WITH active_customers AS (
    SELECT
        customer_id
    FROM shared.dim_customers
    WHERE is_active = TRUE
),
recognized_invoice_revenue AS (
    SELECT
        invoice_id,
        customer_id,
        invoice_amount AS recognized_revenue_usd
    FROM shared.fact_invoices
    WHERE invoice_status = 'POSTED'
      AND currency_code = 'USD'
      AND invoice_date >= DATEADD(day, -89, CURRENT_DATE())
      AND invoice_date <= CURRENT_DATE()
),
recognized_refunds AS (
    SELECT
        invoices.customer_id,
        refunds.refund_amount AS recognized_refund_usd
    FROM shared.fact_refunds AS refunds
    INNER JOIN shared.fact_invoices AS invoices
        ON refunds.invoice_id = invoices.invoice_id
    INNER JOIN active_customers
        ON invoices.customer_id = active_customers.customer_id
    WHERE refunds.refund_status = 'APPROVED'
      AND refunds.currency_code = 'USD'
      AND refunds.refund_date >= DATEADD(day, -89, CURRENT_DATE())
      AND refunds.refund_date <= CURRENT_DATE()
),
net_recognized_revenue AS (
    SELECT
        COALESCE(SUM(invoices.recognized_revenue_usd), 0) AS invoice_revenue_usd,
        COALESCE((SELECT SUM(recognized_refund_usd) FROM recognized_refunds), 0) AS refund_revenue_usd,
        COALESCE(SUM(invoices.recognized_revenue_usd), 0)
            - COALESCE((SELECT SUM(recognized_refund_usd) FROM recognized_refunds), 0)
            AS net_recognized_revenue_usd
    FROM recognized_invoice_revenue AS invoices
    INNER JOIN active_customers
        ON invoices.customer_id = active_customers.customer_id
),
active_customer_count AS (
    SELECT
        COUNT(*) AS active_customers
    FROM active_customers
)
SELECT
    CURRENT_DATE() AS as_of_date,
    DATEADD(day, -89, CURRENT_DATE()) AS revenue_window_start_date,
    CURRENT_DATE() AS revenue_window_end_date,
    revenue.invoice_revenue_usd,
    revenue.refund_revenue_usd,
    revenue.net_recognized_revenue_usd,
    customers.active_customers,
    revenue.net_recognized_revenue_usd / NULLIF(customers.active_customers, 0) AS arpac_trailing_90_day_usd
FROM net_recognized_revenue AS revenue
CROSS JOIN active_customer_count AS customers;