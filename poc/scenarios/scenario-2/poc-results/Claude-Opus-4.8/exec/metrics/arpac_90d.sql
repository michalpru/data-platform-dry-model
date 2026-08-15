-- exec.metrics.arpac_90d.v1  — ARPAC (Average Revenue per Active Customer), trailing 90 days
-- Target runtime/dialect: warehouse / snowflake
-- Grain: reporting_date
--
-- ARPAC = net recognized revenue in USD (from ACTIVE customers only)  /  count of active customers
--
-- This metric reads the governed components dataset exec.reporting.arpac_active_customer_revenue_90d.v1,
-- which already restricts the population to active customers using the certified active-customer
-- definition. So SUM(...) is revenue from active customers only, and COUNT(DISTINCT customer_id) is
-- the certified active-customer count. Neither numerator nor denominator is re-derived here.

SELECT
    reporting_date,
    SUM(recognized_revenue_usd_90d)                                   AS net_recognized_revenue_usd_90d,  -- numerator
    COUNT(DISTINCT customer_id)                                       AS active_customers_90d,             -- denominator
    DIV0(SUM(recognized_revenue_usd_90d), COUNT(DISTINCT customer_id)) AS arpac_90d_usd
FROM exec.reporting.arpac_active_customer_revenue_90d
GROUP BY reporting_date;
