-- executive.metrics.arpac_90d.v1  (Snowflake SQL warehouse)
-- =========================================================================
-- ARPAC (Average Revenue per Active Customer), trailing 90 days, for executive reporting.
-- ARPAC = net recognized revenue USD (active customers only) / distinct active customers.
--
-- This is the thin ratio on top of the governed components dataset
-- executive.datasets.arpac_90d_components.v1. All reuse and the cross-engine precondition
-- for the denominator live in that dataset; this metric only forms the ratio.
-- =========================================================================
CREATE OR REPLACE VIEW EXECUTIVE.METRICS.ARPAC_90D AS
SELECT
    reporting_date,
    net_recognized_revenue_usd,
    active_customer_count,
    net_recognized_revenue_usd / NULLIF(active_customer_count, 0) AS arpac_90d_usd
FROM EXECUTIVE.DATASETS.ARPAC_90D_COMPONENTS;
