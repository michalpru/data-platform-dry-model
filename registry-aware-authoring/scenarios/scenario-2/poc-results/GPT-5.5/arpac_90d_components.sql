-- Reusable trailing-90-day ARPAC components dataset for executive reporting.
--
-- Runtime: Snowflake SQL warehouse.
-- Cross-engine precondition: the certified active-customer binding
-- sales.datasets.commercial_customer_status_90d is currently registered only on Databricks.
-- This SQL assumes that exact registered binding is reachable from the Snowflake warehouse once
-- a governed Snowflake/federated binding is provisioned. No bridge object is invented here.
--
-- Reuses:
-- - sales.datasets.commercial_customer_status_90d.v1 via binding sales.datasets.commercial_customer_status_90d
-- - finance.logic.recognize_revenue.v1 via binding FINANCE.LOGIC.RECOGNIZE_REVENUE

CREATE OR REPLACE VIEW EXECUTIVE_METRICS.ARPAC_90D_COMPONENTS AS
WITH active_customers AS (
    SELECT
        customer_id,
        reporting_date
    FROM sales.datasets.commercial_customer_status_90d
    WHERE is_active_commercial_90d = TRUE
),
reporting_windows AS (
    SELECT DISTINCT
        reporting_date
    FROM active_customers
),
recognized_revenue AS (
    SELECT
        rw.reporting_date,
        rr.CUSTOMER_ID,
        rr.RECOGNIZED_REVENUE_USD
    FROM reporting_windows AS rw
    LEFT JOIN LATERAL TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(
            DATEADD(day, -89, rw.reporting_date),
            rw.reporting_date
        )
    ) AS rr
        ON TRUE
),
customer_revenue AS (
    SELECT
        ac.reporting_date,
        ac.customer_id,
        COALESCE(SUM(rr.RECOGNIZED_REVENUE_USD), 0) AS net_recognized_revenue_usd_90d
    FROM active_customers AS ac
    LEFT JOIN recognized_revenue AS rr
        ON rr.reporting_date = ac.reporting_date
       AND rr.CUSTOMER_ID = ac.customer_id
    GROUP BY
        ac.reporting_date,
        ac.customer_id
)
SELECT
    reporting_date,
    SUM(net_recognized_revenue_usd_90d) AS net_recognized_revenue_usd_90d,
    COUNT(DISTINCT customer_id) AS active_customer_count_90d
FROM customer_revenue
GROUP BY reporting_date;
