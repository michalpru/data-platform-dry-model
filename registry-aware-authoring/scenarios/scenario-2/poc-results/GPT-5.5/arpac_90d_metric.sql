-- Reusable trailing-90-day ARPAC metric definition for executive dashboards.
-- ARPAC = net recognized revenue in USD from active customers / distinct active customers.

CREATE OR REPLACE VIEW EXECUTIVE_METRICS.ARPAC_90D AS
SELECT
    reporting_date,
    net_recognized_revenue_usd_90d,
    active_customer_count_90d,
    net_recognized_revenue_usd_90d / NULLIF(active_customer_count_90d, 0) AS arpac_90d_usd
FROM EXECUTIVE_METRICS.ARPAC_90D_COMPONENTS;
