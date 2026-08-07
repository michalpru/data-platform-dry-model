-- Trailing-90-day ARPAC for executive reporting.
--
-- Reused governed artifacts resolved from the registry:
-- - finance.logic.recognize_revenue.v1 -> FINANCE.LOGIC.RECOGNIZE_REVENUE
-- - sales.datasets.commercial_customer_status_90d.v1 -> sales.datasets.commercial_customer_status_90d
--
-- Registry binding note: recognized revenue resolves to Snowflake/warehouse, while the
-- executive active-customer status resolves only to Databricks. This query assumes the
-- Databricks view is available to the runner under its resolved name, for example through
-- federation or a governed mirror.
--
-- Parameters expected by the query runner:
-- - :as_of_date DATE, inclusive reporting date for the trailing window.

WITH reporting_window AS (
    SELECT
        TO_DATE(:as_of_date) AS as_of_date,
        DATEADD(day, -89, TO_DATE(:as_of_date)) AS window_start_date
),

recognized_revenue AS (
    SELECT
        revenue.customer_id,
        SUM(revenue.recognized_revenue_usd) AS net_recognized_revenue_usd
    FROM reporting_window AS reporting_window
    CROSS JOIN TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(
            reporting_window.window_start_date,
            reporting_window.as_of_date,
            'USD'
        )
    ) AS revenue
    GROUP BY revenue.customer_id
),

active_customers AS (
    SELECT DISTINCT
        customer_status.customer_id
    FROM sales.datasets.commercial_customer_status_90d AS customer_status
    JOIN reporting_window AS reporting_window
        ON customer_status.reporting_date = reporting_window.as_of_date
    WHERE customer_status.is_active_commercial_90d = TRUE
),

metric_inputs AS (
    SELECT
        reporting_window.as_of_date,
        COALESCE(SUM(revenue.net_recognized_revenue_usd), 0) AS net_recognized_revenue_usd,
        COUNT(active_customers.customer_id) AS active_customer_count
    FROM reporting_window AS reporting_window
    LEFT JOIN active_customers
        ON TRUE
    LEFT JOIN recognized_revenue AS revenue
        ON revenue.customer_id = active_customers.customer_id
    GROUP BY reporting_window.as_of_date
)

SELECT
    as_of_date,
    DATEADD(day, -89, as_of_date) AS window_start_date,
    net_recognized_revenue_usd,
    active_customer_count,
    net_recognized_revenue_usd / NULLIF(active_customer_count, 0) AS trailing_90_day_arpac_usd
FROM metric_inputs;