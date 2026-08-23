CREATE OR REPLACE VIEW sales.datasets.commercial_customer_status_90d AS
SELECT
    c.customer_id,
    d.reporting_date,
    MAX(
        CASE
            WHEN e.event_date >= date_sub(d.reporting_date, 90)
             AND e.event_date <= d.reporting_date
             AND e.event_type IN ('paid_invoice', 'active_subscription', 'committed_order')
            THEN true
            ELSE false
        END
    ) AS is_active_commercial_90d
FROM sales.datasets.dim_customers AS c
CROSS JOIN sales.datasets.reporting_calendar AS d
LEFT JOIN sales.datasets.fact_commercial_events AS e
    ON e.customer_id = c.customer_id
GROUP BY c.customer_id, d.reporting_date;
