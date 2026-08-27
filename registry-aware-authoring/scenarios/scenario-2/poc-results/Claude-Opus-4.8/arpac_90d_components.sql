-- executive.datasets.arpac_90d_components.v1  (Snowflake SQL warehouse)
-- =========================================================================
-- Reporting-date-grain components for the trailing-90-day ARPAC metric.
-- Grain: reporting_date. Emits net_recognized_revenue_usd (active customers only)
-- and active_customer_count.
--
-- REUSE (no revenue or active-customer logic is re-derived here):
--   Numerator source : finance.logic.recognize_revenue.v1  (certified, enterprise_canonical)
--                      binding warehouse:snowflake:FINANCE.LOGIC.RECOGNIZE_REVENUE  [Snowflake UDF]
--   Denominator source: sales.datasets.commercial_customer_status_90d.v1
--                      (certified, enterprise_canonical — the executive active-customer definition)
--                      binding databricks:sales.datasets.commercial_customer_status_90d  [Databricks view]
--
-- CROSS-ENGINE PRECONDITION (denominator):
--   The executive active-customer definition resolves ONLY to a Databricks binding; there is NO
--   Snowflake binding in the registry. It is referenced below under its resolved binding ref
--   under the precondition "assumes reachable from the Snowflake warehouse once a binding is
--   provisioned" (portable-SQL rebuild, or a shared/federated view registered as an additional
--   binding). No Snowflake bridge object is fabricated. Do NOT substitute the Sales billed-proxy
--   (sales.datasets.active_customer_90d.v1), the Marketing login proxy, or DIM_CUSTOMERS.IS_ACTIVE
--   — the registry flags each of those as NOT the executive definition.
-- =========================================================================
CREATE OR REPLACE VIEW EXECUTIVE.DATASETS.ARPAC_90D_COMPONENTS AS
WITH
-- DENOMINATOR: distinct active customers at the as-of reporting date, per the certified
-- executive active-customer definition. Columns confirmed from the resolved binding source
-- (customer_id, reporting_date, is_active_commercial_90d).
active_customers AS (
    SELECT DISTINCT s.customer_id
    FROM sales.datasets.commercial_customer_status_90d AS s   -- << resolved Databricks binding; see cross-engine precondition
    WHERE s.reporting_date = CURRENT_DATE()
      AND s.is_active_commercial_90d = TRUE
),
-- NUMERATOR SOURCE: net recognized revenue in USD over the trailing 90 days ending today.
-- Signature and output columns confirmed from the UDF source
-- (P_START_DATE DATE, P_END_DATE DATE) -> (CUSTOMER_ID, ..., RECOGNIZED_REVENUE_USD).
-- Refund/credit-note netting is already carried in RECOGNIZED_REVENUE_USD.
recognized_revenue AS (
    SELECT
        r.CUSTOMER_ID,
        r.RECOGNIZED_REVENUE_USD
    FROM TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(DATEADD(DAY, -90, CURRENT_DATE()), CURRENT_DATE())
    ) AS r
),
-- Count ONLY revenue from customers in the denominator (inner join). Non-active customers excluded.
active_revenue AS (
    SELECT r.RECOGNIZED_REVENUE_USD
    FROM recognized_revenue AS r
    JOIN active_customers AS a
      ON a.customer_id = r.CUSTOMER_ID
)
SELECT
    CURRENT_DATE()                                              AS reporting_date,
    COALESCE(SUM(ar.RECOGNIZED_REVENUE_USD), 0)                 AS net_recognized_revenue_usd,
    (SELECT COUNT(DISTINCT customer_id) FROM active_customers)  AS active_customer_count
FROM active_revenue AS ar;
