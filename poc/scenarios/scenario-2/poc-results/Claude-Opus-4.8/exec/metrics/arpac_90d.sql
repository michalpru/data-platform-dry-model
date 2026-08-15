-- exec.metrics.arpac_90d  (Snowflake SQL table function)
-- =========================================================================
-- Registry FQN (proposed): exec.metrics.arpac_90d.v1  (metric / callable logic)
-- Owner: executive-analytics | Lifecycle: proposed
--
-- Reusable trailing-90-day ARPAC (Average Revenue per Active Customer) for executive reporting.
-- Other executive dashboards adopt this by calling the function with an as-of reporting date.
--
--   ARPAC(90d) = net recognized revenue USD (trailing 90d, active customers only)
--                -------------------------------------------------------------------
--                             distinct count of active customers
--
-- Both operands come from ONE governed building-block dataset (exec.datasets.arpac_components_90d.v1),
-- which already restricts revenue to the active-customer population. The metric only aggregates:
--   * numerator   = SUM(trailing-90d net recognized revenue) over active customers
--   * denominator = COUNT(DISTINCT active customer)
-- DIV0 guards the empty-population case (returns 0 when there are no active customers).
--
-- Reuse provenance (nothing re-derived here):
--   * exec.datasets.arpac_components_90d.v1  -> composes the two certified inputs below
--   * finance.logic.recognize_revenue.v1     -> net recognized revenue USD (Snowflake UDF)
--   * sales.datasets.commercial_customer_status_90d.v1 -> active-customer definition (Databricks;
--       reachability precondition documented in the components dataset).
-- =========================================================================
CREATE OR REPLACE FUNCTION EXEC.METRICS.ARPAC_90D(
    P_REPORTING_DATE DATE
)
RETURNS TABLE (
    REPORTING_DATE                  DATE,
    NET_RECOGNIZED_REVENUE_USD_90D  NUMBER(18, 2),
    ACTIVE_CUSTOMERS_90D            NUMBER(38, 0),
    ARPAC_90D_USD                   NUMBER(18, 2)
)
LANGUAGE SQL
AS
$$
    SELECT
        P_REPORTING_DATE                                                AS REPORTING_DATE,
        SUM(c.RECOGNIZED_REVENUE_USD_90D)                               AS NET_RECOGNIZED_REVENUE_USD_90D,
        COUNT(DISTINCT c.CUSTOMER_ID)                                   AS ACTIVE_CUSTOMERS_90D,
        DIV0(
            SUM(c.RECOGNIZED_REVENUE_USD_90D),
            COUNT(DISTINCT c.CUSTOMER_ID)
        )                                                               AS ARPAC_90D_USD
    FROM TABLE(EXEC.DATASETS.ARPAC_COMPONENTS_90D(P_REPORTING_DATE)) AS c
$$;
