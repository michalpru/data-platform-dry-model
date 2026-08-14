-- Reusable trailing-90-day ARPAC metric query for executive reporting.
-- Bind :as_of_date to the reporting date. The 90-day window is inclusive:
-- DATEADD(day, -89, as_of_date) through as_of_date.
WITH params AS (
    SELECT COALESCE(TO_DATE(:as_of_date), CURRENT_DATE()) AS as_of_date
),
active_customers AS (
    SELECT
        c.customer_id
    FROM shared.dim_customers AS c
    WHERE c.is_active = TRUE
),
posted_invoice_revenue AS (
    SELECT
        i.customer_id,
        SUM(i.invoice_amount) AS revenue_amount_usd
    FROM shared.fact_invoices AS i
    INNER JOIN active_customers AS ac
        ON ac.customer_id = i.customer_id
    CROSS JOIN params AS p
    WHERE i.invoice_status = 'POSTED'
        AND i.currency_code = 'USD'
        AND i.invoice_date BETWEEN DATEADD(day, -89, p.as_of_date) AND p.as_of_date
    GROUP BY i.customer_id
),
approved_refunds AS (
    SELECT
        i.customer_id,
        SUM(r.refund_amount) AS refund_amount_usd
    FROM shared.fact_refunds AS r
    INNER JOIN shared.fact_invoices AS i
        ON i.invoice_id = r.invoice_id
    INNER JOIN active_customers AS ac
        ON ac.customer_id = i.customer_id
    CROSS JOIN params AS p
    WHERE r.refund_status = 'APPROVED'
        AND r.currency_code = 'USD'
        AND i.invoice_status = 'POSTED'
        AND i.currency_code = 'USD'
        AND r.refund_date BETWEEN DATEADD(day, -89, p.as_of_date) AND p.as_of_date
    GROUP BY i.customer_id
),
net_recognized_revenue AS (
    SELECT
        ac.customer_id,
        COALESCE(pir.revenue_amount_usd, 0) - COALESCE(ar.refund_amount_usd, 0) AS net_revenue_amount_usd
    FROM active_customers AS ac
    LEFT JOIN posted_invoice_revenue AS pir
        ON pir.customer_id = ac.customer_id
    LEFT JOIN approved_refunds AS ar
        ON ar.customer_id = ac.customer_id
),
metric_inputs AS (
    SELECT
        COUNT(DISTINCT ac.customer_id) AS active_customer_count,
        COALESCE(SUM(nrr.net_revenue_amount_usd), 0) AS net_recognized_revenue_usd
    FROM active_customers AS ac
    LEFT JOIN net_recognized_revenue AS nrr
        ON nrr.customer_id = ac.customer_id
)
SELECT
    p.as_of_date,
    DATEADD(day, -89, p.as_of_date) AS window_start_date,
    p.as_of_date AS window_end_date,
    mi.net_recognized_revenue_usd,
    mi.active_customer_count,
    mi.net_recognized_revenue_usd / NULLIF(mi.active_customer_count, 0) AS arpac_trailing_90_day_usd
FROM metric_inputs AS mi
CROSS JOIN params AS p;
