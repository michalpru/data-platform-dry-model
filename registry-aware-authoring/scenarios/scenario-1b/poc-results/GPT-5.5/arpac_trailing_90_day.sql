-- Reusable trailing-90-day ARPAC reference implementation for executive reporting.
--
-- Required inputs:
--   :as_of_date                 DATE, inclusive reporting date.
--   :trailing_days              INTEGER, default 90.
--   analytics.active_customers  Relation materialized from marketing.logic.active_customer
--                               for the same :as_of_date and :trailing_days.
--
-- ARPAC = net recognized revenue in USD / distinct active customers.

WITH params AS (
    SELECT
        CAST(:as_of_date AS DATE)                  AS as_of_date,
        COALESCE(:trailing_days, 90)               AS trailing_days,
        DATEADD(day, -COALESCE(:trailing_days, 90), CAST(:as_of_date AS DATE)) AS window_start
),

active_customer_denominator AS (
    SELECT DISTINCT
        ac.customer_id
    FROM analytics.active_customers AS ac
),

invoice_revenue_in_scope AS (
    SELECT
        ir.customer_id,
        ir.invoice_id,
        ir.revenue_date,
        ir.invoice_revenue_usd
    FROM finance.invoice_revenue AS ir
    CROSS JOIN params AS p
    JOIN active_customer_denominator AS ac
      ON ac.customer_id = ir.customer_id
    WHERE ir.revenue_date BETWEEN p.window_start AND p.as_of_date
),

approved_refunds_in_scope AS (
    SELECT
        i.customer_id,
        r.refund_id,
        r.refund_date,
                nc.converted_amount AS refund_amount_usd
    FROM shared.fact_refunds AS r
    JOIN shared.fact_invoices AS i
      ON i.invoice_id = r.invoice_id
    JOIN active_customer_denominator AS ac
      ON ac.customer_id = i.customer_id
        CROSS JOIN TABLE(finance.normalize_currency(
                r.refund_amount,
                r.currency_code,
                'USD',
                CAST(r.refund_date AS DATE)
        )) AS nc
    CROSS JOIN params AS p
    WHERE r.refund_status = 'APPROVED'
      AND r.refund_date BETWEEN p.window_start AND p.as_of_date
),

active_customer_count AS (
    SELECT
        COUNT(DISTINCT customer_id) AS active_customer_count
    FROM active_customer_denominator
),

revenue_totals AS (
    SELECT
        COALESCE(SUM(invoice_revenue_usd), 0) AS gross_recognized_revenue_usd
    FROM invoice_revenue_in_scope
),

refund_totals AS (
    SELECT
        COALESCE(SUM(refund_amount_usd), 0) AS approved_refunds_usd
    FROM approved_refunds_in_scope
)

SELECT
    p.as_of_date,
    p.trailing_days,
    acc.active_customer_count,
    rt.gross_recognized_revenue_usd,
    ft.approved_refunds_usd,
    rt.gross_recognized_revenue_usd - ft.approved_refunds_usd AS net_recognized_revenue_usd,
    ROUND(
        (rt.gross_recognized_revenue_usd - ft.approved_refunds_usd)
        / NULLIF(acc.active_customer_count, 0),
        2
    ) AS arpac_usd
FROM params AS p
CROSS JOIN active_customer_count AS acc
CROSS JOIN revenue_totals AS rt
CROSS JOIN refund_totals AS ft;