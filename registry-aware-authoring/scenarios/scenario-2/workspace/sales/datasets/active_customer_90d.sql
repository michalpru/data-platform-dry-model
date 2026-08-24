-- Databricks / Spark SQL
-- Active-customer status over the trailing 90 days, per reporting_date.
CREATE OR REPLACE VIEW sales.datasets.active_customer_90d AS
WITH reporting_dates AS (
    SELECT DISTINCT invoice_date AS reporting_date
    FROM shared.fact_invoices
)
SELECT
    c.customer_id,
    d.reporting_date,
    MAX(
        CASE
            WHEN i.invoice_status = 'POSTED'
             AND i.invoice_date >= date_sub(d.reporting_date, 90)
             AND i.invoice_date <= d.reporting_date
            THEN true
            ELSE false
        END
    ) AS is_active_customer_90d
FROM shared.dim_customers AS c
CROSS JOIN reporting_dates AS d
LEFT JOIN shared.fact_invoices AS i
    ON i.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    d.reporting_date;
