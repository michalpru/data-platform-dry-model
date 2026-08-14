-- Reusable executive metric: trailing-90-day Average Revenue per Active Customer (ARPAC).
-- Source scope: poc/scenarios/scenario-1a/workspace only.

CREATE OR REPLACE VIEW shared.metric_arpac_trailing_90_days AS
WITH active_customers AS (
    SELECT
        customer_id
    FROM shared.dim_customers
    WHERE is_active = TRUE
),
posted_invoice_revenue_usd AS (
    SELECT
        SUM(i.invoice_amount) AS recognized_revenue_usd
    FROM shared.fact_invoices AS i
    INNER JOIN active_customers AS ac
        ON i.customer_id = ac.customer_id
    WHERE i.invoice_status = 'POSTED'
      AND i.currency_code = 'USD'
      AND i.invoice_date >= DATEADD(day, -90, CURRENT_DATE)
      AND i.invoice_date < DATEADD(day, 1, CURRENT_DATE)
),
approved_refunds_usd AS (
    SELECT
        SUM(r.refund_amount) AS refund_revenue_usd
    FROM shared.fact_refunds AS r
    INNER JOIN shared.fact_invoices AS i
        ON r.invoice_id = i.invoice_id
    INNER JOIN active_customers AS ac
        ON i.customer_id = ac.customer_id
    WHERE r.refund_status = 'APPROVED'
      AND r.currency_code = 'USD'
      AND r.refund_date >= DATEADD(day, -90, CURRENT_DATE)
      AND r.refund_date < DATEADD(day, 1, CURRENT_DATE)
),
active_customer_denominator AS (
    SELECT
        COUNT(DISTINCT customer_id) AS active_customer_count
    FROM active_customers
),
metric_inputs AS (
    SELECT
        CURRENT_DATE AS metric_as_of_date,
        COALESCE(pir.recognized_revenue_usd, 0) - COALESCE(ar.refund_revenue_usd, 0) AS net_recognized_revenue_usd,
        acd.active_customer_count
    FROM posted_invoice_revenue_usd AS pir
    CROSS JOIN approved_refunds_usd AS ar
    CROSS JOIN active_customer_denominator AS acd
)
SELECT
    metric_as_of_date,
    net_recognized_revenue_usd,
    active_customer_count,
    net_recognized_revenue_usd / NULLIF(active_customer_count, 0) AS arpac_trailing_90_days_usd
FROM metric_inputs;