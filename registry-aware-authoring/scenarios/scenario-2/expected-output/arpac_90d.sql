-- arpac_90d.sql — SCENARIO 2 expected output (registry-aware; Snowflake SQL)
-- =========================================================================
-- Registry FQN: enterprise.semantic.arpac_90d.v1
--
-- The DRY Reuse agent resolved certified artifacts from the registry BEFORE authoring. Because the
-- two inputs live on DIFFERENT engines, resolve_binding returned two different physical objects:
--   * net recognized revenue -> finance.logic.recognize_revenue.v1
--       resolved SNOWFLAKE binding: FINANCE.LOGIC.RECOGNIZE_REVENUE (recognition rules +
--       refund netting + currency normalization; native table UDF)
--   * active customer         -> sales.datasets.commercial_customer_status_90d.v1
--       resolved DATABRICKS binding: sales.datasets.commercial_customer_status_90d (Sales-owned,
--       certified 90-day commercial-activity view)
--
-- CROSS-ENGINE GAP — flagged, NOT fabricated: there is no Snowflake binding for the Sales status
-- view. The cross-engine join is materialized once in the governed components dataset
-- enterprise.datasets.customer_arpac_components_90d (see customer_arpac_components_90d.sql), which
-- references the resolved Databricks binding under an explicit "reachable from Snowflake once a
-- binding is provisioned" precondition. No bridge object is invented; provisioning it is an
-- integration requirement, out of scope for this PoC.
--
-- POPULATIONS (certified definition):
--   denominator = distinct count of customers with is_active_commercial_90d = TRUE on :as_of_date
--   numerator   = net recognized revenue in USD over the trailing 90 days, counting ONLY revenue
--                 from those active customers (revenue from non-active customers is excluded)
--
-- Reporting date is a PARAMETER (:as_of_date), not CURRENT_DATE(), so executive point-in-time
-- snapshots (e.g. month-end packs) are reproducible. This file is the ONLY genuinely new logic:
-- the ARPAC ratio, authored in the consumer's single dialect (Snowflake) on top of that dataset.
--
-- Reuse is not limited to raw SQL. recognize_revenue is one certified identity with two Snowflake
-- bindings — the native UDF above and a dbt macro (dry_finance_macros.recognized_revenue_relation); a
-- dbt model would `{{ recognized_revenue_relation(...) }}` and reuse the exact same governed logic.
-- dbt gives reuse INSIDE dbt on one engine; the registry records that the macro and the UDF are the
-- same certified capability AND spans the Databricks stack that dbt on Snowflake never sees.
-- =========================================================================
SELECT
    :as_of_date AS reporting_date,
    SUM(CASE WHEN is_active_commercial_90d
             THEN net_recognized_revenue_90d_usd
             ELSE 0 END)
        / NULLIF(COUNT_IF(is_active_commercial_90d), 0) AS arpac_90d_usd
FROM analytics.enterprise.customer_arpac_components_90d
WHERE reporting_date = :as_of_date;
