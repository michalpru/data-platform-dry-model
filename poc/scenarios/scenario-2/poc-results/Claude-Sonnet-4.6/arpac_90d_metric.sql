-- =============================================================================
-- exec.metrics.arpac_90d
-- Metric: Average Revenue per Active Customer — Trailing 90 Days
-- Grain: REPORTING_DATE
--
-- Formula:
--   ARPAC_USD = SUM(NET_REVENUE_USD) / COUNT(DISTINCT CUSTOMER_ID)
--
--   Numerator  : total net recognized revenue (USD) from active customers only,
--                over the trailing 90 days ending on each REPORTING_DATE.
--   Denominator: count of distinct active customers per the enterprise definition.
--
-- Both numerator and denominator are sourced from exec.datasets.arpac_components_90d,
-- which guarantees the same customer population drives both sides of the ratio.
--
-- REUSES (via exec.datasets.arpac_components_90d):
--   - sales.datasets.commercial_customer_status_90d.v1  (denominator population)
--     certified | enterprise_canonical | owner: sales-analytics
--   - finance.logic.recognize_revenue.v1                (numerator revenue)
--     certified | enterprise_canonical | owner: finance-analytics
--
-- NOTE: The ARPAC_USD output is NULL (not zero) when no active customers exist
-- for a reporting date, to avoid a misleading $0 result from a zero denominator.
-- =============================================================================

CREATE OR REPLACE VIEW exec.metrics.arpac_90d AS

SELECT
    REPORTING_DATE,
    SUM(NET_REVENUE_USD)          AS NET_REVENUE_USD_TRAILING_90D,
    COUNT(DISTINCT CUSTOMER_ID)   AS ACTIVE_CUSTOMER_COUNT,
    CASE
        WHEN COUNT(DISTINCT CUSTOMER_ID) = 0 THEN NULL
        ELSE SUM(NET_REVENUE_USD) / COUNT(DISTINCT CUSTOMER_ID)
    END                           AS ARPAC_USD
FROM exec.datasets.arpac_components_90d
GROUP BY REPORTING_DATE;
