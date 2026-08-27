-- Reusable executive-reporting metric implementation
-- Metric: trailing-90-day ARPAC (Average Revenue per Active Customer)
--
-- Reuse bindings:
--   Denominator: sales.datasets.active_customer_90d
--   Numerator:   FINANCE.LOGIC.RECOGNIZE_REVENUE, which reuses
--                FINANCE.DATASETS.FACT_BILLABLE_EVENTS and
--                FINANCE.LOGIC.NORMALIZE_CURRENCY.
--
-- Window convention:
--   Uses the same inclusive trailing window as sales.datasets.active_customer_90d:
--   reporting_date - 90 days through reporting_date.

CREATE OR REPLACE VIEW executive_reporting.metrics.arpac_trailing_90d AS
WITH active_customers AS (
    SELECT
        reporting_date,
        customer_id
    FROM sales.datasets.active_customer_90d
    WHERE is_active_customer_90d = TRUE
),

reporting_dates AS (
    SELECT DISTINCT reporting_date
    FROM active_customers
),

recognized_revenue AS (
    SELECT
        d.reporting_date,
        r.customer_id,
        r.billable_event_id,
        r.recognition_date,
        r.event_type,
        r.source_currency,
        r.recognized_revenue_usd
    FROM reporting_dates AS d,
    LATERAL TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(
            DATEADD(day, -90, d.reporting_date),
            d.reporting_date
        )
    ) AS r
),

revenue_from_active_customers AS (
    SELECT
        a.reporting_date,
        r.customer_id,
        r.billable_event_id,
        r.recognized_revenue_usd
    FROM active_customers AS a
    INNER JOIN recognized_revenue AS r
        ON r.reporting_date = a.reporting_date
       AND r.customer_id = a.customer_id
)

SELECT
    a.reporting_date,
    COUNT(DISTINCT a.customer_id) AS active_customer_count_90d,
    COALESCE(SUM(r.recognized_revenue_usd), 0) AS net_recognized_revenue_usd_90d,
    COALESCE(SUM(r.recognized_revenue_usd), 0)
        / NULLIF(COUNT(DISTINCT a.customer_id), 0) AS arpac_usd_90d
FROM active_customers AS a
LEFT JOIN revenue_from_active_customers AS r
    ON r.reporting_date = a.reporting_date
   AND r.customer_id = a.customer_id
GROUP BY a.reporting_date;
