-- exec.metrics.arpac_90d  (Snowflake SQL view — metric layer)
-- =========================================================================
-- Registry FQN : exec.metrics.arpac_90d.v1  (semantic contract / metric)
-- Owner        : exec-analytics  |  Lifecycle: shared (pending certification)
--
-- ARPAC = Average Revenue Per Active Customer, trailing 90 days.
-- Formula: SUM(NET_RECOGNIZED_REVENUE_USD) / COUNT(DISTINCT CUSTOMER_ID)
--
-- Reads from the components dataset:
--   exec.metrics.arpac_90d_components.v1
--   Snowflake object: EXEC.METRICS.ARPAC_90D_COMPONENTS (view)
--
-- REPORTING_DATE is always CURRENT_DATE (evaluated at query time by the
-- components view), so this view returns a single row per query execution.
--
-- DIV0 returns 0 when active-customer count is zero (safe division).
-- =========================================================================

CREATE OR REPLACE VIEW EXEC.METRICS.ARPAC_90D AS
SELECT
    REPORTING_DATE,
    COUNT(DISTINCT CUSTOMER_ID)              AS ACTIVE_CUSTOMER_COUNT,
    SUM(NET_RECOGNIZED_REVENUE_USD)          AS TOTAL_NET_RECOGNIZED_REVENUE_USD,
    DIV0(
        SUM(NET_RECOGNIZED_REVENUE_USD),
        COUNT(DISTINCT CUSTOMER_ID)
    )                                        AS ARPAC_USD
FROM EXEC.METRICS.ARPAC_90D_COMPONENTS
GROUP BY
    REPORTING_DATE;
