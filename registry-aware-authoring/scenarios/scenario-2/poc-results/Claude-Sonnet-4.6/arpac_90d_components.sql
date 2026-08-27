-- exec.metrics.arpac_90d_components  (Snowflake SQL view)
-- =========================================================================
-- Registry FQN : exec.metrics.arpac_90d_components.v1  (queryable dataset)
-- Owner        : exec-analytics  |  Lifecycle: shared (pending certification)
-- Grain        : CUSTOMER_ID — one row per active customer as of CURRENT_DATE
--
-- ARPAC trailing-90-day components dataset.
--
-- DENOMINATOR population
--   Artifact : sales.datasets.commercial_customer_status_90d.v1
--   Authority : REGISTERED_CANONICAL | certified | enterprise_canonical
--   This is the enterprise executive active-customer definition used by all
--   executive dashboards.  Filters: IS_ACTIVE_COMMERCIAL_90D = TRUE for
--   REPORTING_DATE = CURRENT_DATE.
--
--   *** BINDING GAP — INTEGRATION REQUIREMENT ***
--   sales.datasets.commercial_customer_status_90d.v1 is certified on Databricks
--   only.  No Snowflake warehouse binding exists in the registry.
--   The provisional Snowflake object name SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D
--   is used below.  Provisioning that binding (via the portable-SQL framework or a
--   registered federated / shared view) is an integration requirement.
--   This view is correct and runnable the moment the binding is provisioned.
--
-- NUMERATOR
--   Artifact : finance.logic.recognize_revenue.v1
--   Authority : REGISTERED_CANONICAL | certified | enterprise_canonical
--   Snowflake binding: FINANCE.LOGIC.RECOGNIZE_REVENUE(P_START_DATE DATE, P_END_DATE DATE)
--   Object type: UDF (table function)
--   Confirmed return columns (source: finance/logic/recognize_revenue.sql):
--     CUSTOMER_ID, BILLABLE_EVENT_ID, RECOGNITION_DATE, EVENT_TYPE,
--     SOURCE_CURRENCY, RECOGNIZED_REVENUE_USD
--   Net recognized revenue in USD over the trailing 90 days.
--   Refund/credit-note netting is already carried in the UDF's signed NET_AMOUNT;
--   do NOT re-derive revenue from SHARED.DATASETS.FACT_INVOICES directly.
--
-- Revenue from customers NOT in the active set is excluded by design: the query
-- drives from the active-customer set (ac) and left-joins revenue (rev), so
-- only rows with a matching active CUSTOMER_ID carry revenue.
-- =========================================================================

CREATE OR REPLACE VIEW EXEC.METRICS.ARPAC_90D_COMPONENTS AS
SELECT
    ac.CUSTOMER_ID,
    CURRENT_DATE                                 AS REPORTING_DATE,
    COALESCE(SUM(rev.RECOGNIZED_REVENUE_USD), 0) AS NET_RECOGNIZED_REVENUE_USD
FROM SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D AS ac  -- PRECONDITION: Snowflake binding required (see header)
LEFT JOIN TABLE(
    FINANCE.LOGIC.RECOGNIZE_REVENUE(
        DATEADD('day', -90, CURRENT_DATE),
        CURRENT_DATE
    )
) AS rev
    ON rev.CUSTOMER_ID = ac.CUSTOMER_ID
WHERE ac.IS_ACTIVE_COMMERCIAL_90D = TRUE
  AND ac.REPORTING_DATE = CURRENT_DATE
GROUP BY
    ac.CUSTOMER_ID;
