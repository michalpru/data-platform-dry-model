-- Trailing-90-day ARPAC (Average Revenue per Active Customer)
-- Target warehouse: Snowflake
--
-- Reused workspace artifacts:
--   * shared.fact_invoices for posted invoice revenue
--   * shared.fact_refunds for approved refund / credit-note offsets
--   * shared.dim_customers.is_active for the executive active-customer definition
--
-- USD handling:
--   The allowed workspace contains currency_code fields but no FX rate table or
--   conversion function. This view computes a numeric ARPAC only when every
--   trailing-window revenue event is already denominated in USD. If non-USD
--   recognized revenue exists, arpac_90d_usd is NULL and metric_status explains
--   the missing reusable FX artifact instead of silently reporting a wrong metric.

CREATE SCHEMA IF NOT EXISTS executive;

CREATE OR REPLACE VIEW executive.arpac_trailing_90_day AS
WITH reporting_window AS (
    SELECT
        CURRENT_DATE() AS as_of_date,
        DATEADD(day, -89, CURRENT_DATE()) AS window_start_date
),

posted_invoice_revenue AS (
    SELECT
        i.invoice_id,
        i.customer_id,
        i.invoice_date AS recognized_date,
        i.invoice_amount AS recognized_amount,
        i.currency_code,
        'POSTED_INVOICE' AS revenue_event_type
    FROM shared.fact_invoices AS i
    CROSS JOIN reporting_window AS w
    WHERE i.invoice_status = 'POSTED'
      AND i.invoice_date BETWEEN w.window_start_date AND w.as_of_date
),

approved_refund_offsets AS (
    SELECT
        r.invoice_id,
        i.customer_id,
        r.refund_date AS recognized_date,
        -r.refund_amount AS recognized_amount,
        r.currency_code,
        'APPROVED_REFUND' AS revenue_event_type
    FROM shared.fact_refunds AS r
    INNER JOIN shared.fact_invoices AS i
        ON i.invoice_id = r.invoice_id
    CROSS JOIN reporting_window AS w
    WHERE r.refund_status = 'APPROVED'
      AND r.refund_date BETWEEN w.window_start_date AND w.as_of_date
),

recognized_revenue_events AS (
    SELECT * FROM posted_invoice_revenue
    UNION ALL
    SELECT * FROM approved_refund_offsets
),

revenue_rollup AS (
    SELECT
        COALESCE(SUM(IFF(currency_code = 'USD', recognized_amount, 0)), 0) AS net_recognized_revenue_usd,
        COALESCE(SUM(IFF(currency_code <> 'USD', 1, 0)), 0) AS non_usd_revenue_event_count
    FROM recognized_revenue_events
),

non_usd_currency_rollup AS (
    SELECT
        LISTAGG(currency_code, ', ') WITHIN GROUP (ORDER BY currency_code) AS non_usd_currency_codes
    FROM (
        SELECT DISTINCT currency_code
        FROM recognized_revenue_events
        WHERE currency_code <> 'USD'
    )
),

active_customer_rollup AS (
    SELECT
        COUNT(*) AS active_customer_count
    FROM shared.dim_customers
    WHERE is_active = TRUE
)

SELECT
    w.as_of_date,
    w.window_start_date,
    r.net_recognized_revenue_usd,
    a.active_customer_count,
    CASE
        WHEN r.non_usd_revenue_event_count = 0
            THEN r.net_recognized_revenue_usd / NULLIF(a.active_customer_count, 0)
        ELSE NULL
    END AS arpac_90d_usd,
    r.non_usd_revenue_event_count,
    c.non_usd_currency_codes,
    CASE
        WHEN a.active_customer_count = 0 THEN 'BLOCKED_NO_ACTIVE_CUSTOMERS'
        WHEN r.non_usd_revenue_event_count > 0 THEN 'BLOCKED_MISSING_FX_REUSE'
        ELSE 'READY'
    END AS metric_status
FROM reporting_window AS w
CROSS JOIN revenue_rollup AS r
CROSS JOIN non_usd_currency_rollup AS c
CROSS JOIN active_customer_rollup AS a;
