-- exec.reporting.arpac_active_customer_revenue_90d.v1  (queryable dataset — ARPAC components)
-- Target runtime/dialect: warehouse / snowflake
-- Grain: reporting_date x customer_id  (ACTIVE customers only)
-- Purpose: trailing-90d net recognized revenue in USD per ACTIVE customer. These are the
--          per-customer components that feed the ARPAC ratio metric exec.metrics.arpac_90d.v1.
--          Restricting the population to active customers here guarantees the numerator counts
--          ONLY revenue from the denominator set (non-active-customer revenue is excluded).
--
-- REUSE (resolved via the registry — NOT re-derived here):
--   NUMERATOR   finance.logic.recognize_revenue.v1        [certified, enterprise_canonical, finance-analytics]
--               resolved binding: warehouse/snowflake UDF
--               FINANCE.LOGIC.RECOGNIZE_REVENUE(P_START_DATE DATE, P_END_DATE DATE)
--               -> CUSTOMER_ID, BILLABLE_EVENT_ID, RECOGNITION_DATE, EVENT_TYPE,
--                  SOURCE_CURRENCY, RECOGNIZED_REVENUE_USD
--               (USD normalization + refund/credit netting are already inside this rule.)
--   DENOMINATOR sales.datasets.commercial_customer_status_90d.v1 [certified, enterprise_canonical, sales-analytics]
--               resolved binding: databricks view sales.datasets.commercial_customer_status_90d
--               -> customer_id, reporting_date, is_active_commercial_90d (boolean)
--               This is the enterprise active-customer definition used by executive dashboards.
--
-- >>> CROSS-ENGINE PRECONDITION (integration gap — do not treat as satisfied) <<<
--   The active-customer definition is bound ONLY to databricks. resolve_binding returned NO
--   warehouse/snowflake binding for it. This snowflake dataset therefore assumes that view is
--   reachable from the warehouse via a binding provisioned under the SAME registry FQN
--   (sales.datasets.commercial_customer_status_90d.v1): either a portable-SQL materialization
--   into snowflake, or a federated / shared view registered as an ADDITIONAL binding.
--   No bridging physical object name is invented here. The reference below resolves the moment
--   that warehouse binding exists; until then ACTIVE_CUSTOMERS is UNRESOLVED on snowflake.
--   Join-key note: NUMERATOR CUSTOMER_ID is NUMBER(38,0); the databricks customer_id type must
--   be reconciled when the warehouse binding is provisioned.

WITH params AS (
    SELECT :reporting_date::DATE AS reporting_date
),

-- Denominator population: distinct ACTIVE customers as-of reporting_date (certified definition).
active_customers AS (
    SELECT DISTINCT s.customer_id
    FROM sales.datasets.commercial_customer_status_90d AS s   -- databricks binding; see CROSS-ENGINE PRECONDITION
    CROSS JOIN params AS p
    WHERE s.reporting_date = p.reporting_date
      AND s.is_active_commercial_90d = TRUE
),

-- Numerator source: certified net recognized revenue (USD) over the trailing-90d window.
-- Window is aligned with the active-customer definition's own 90-day lookback
-- (event_date >= reporting_date - 90 AND <= reporting_date), so numerator and denominator
-- share one consistent trailing-90d window.
recognized AS (
    SELECT
        r.CUSTOMER_ID          AS customer_id,
        r.RECOGNIZED_REVENUE_USD AS recognized_revenue_usd
    FROM params AS p,
         TABLE(
             FINANCE.LOGIC.RECOGNIZE_REVENUE(
                 DATEADD(DAY, -90, p.reporting_date),  -- P_START_DATE
                 p.reporting_date                      -- P_END_DATE
             )
         ) AS r
)

SELECT
    p.reporting_date,
    ac.customer_id,
    COALESCE(SUM(r.recognized_revenue_usd), 0)::NUMBER(18, 2) AS recognized_revenue_usd_90d
FROM params AS p
CROSS JOIN active_customers AS ac
LEFT JOIN recognized AS r
    ON r.customer_id = ac.customer_id   -- keeps ONLY active-customer revenue; excludes all others
GROUP BY p.reporting_date, ac.customer_id;
