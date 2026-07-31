-- customer_arpac_components_90d.sql — SCENARIO 2 generated output (enterprise dataset; Snowflake SQL)
-- =========================================================================
-- Registry FQN: enterprise.datasets.customer_arpac_components_90d.v1
-- Grain:        (customer_id, reporting_date)
--
-- This is one of the two artifacts the DRY Reuse agent actually AUTHORS in scenario 2 — the small,
-- missing composition that joins two already-certified inputs. Nothing here re-implements a
-- revenue-recognition rule, a netting rule, a currency rule, or an activity window; each of those
-- is a resolved, certified binding.
--
-- CROSS-ENGINE COMPOSITION (the point of this scenario):
--   * net recognized revenue -> finance.logic.recognize_revenue.v1
--       resolved SNOWFLAKE binding: FINANCE.LOGIC.RECOGNIZE_REVENUE (native table UDF)
--   * active-customer status  -> sales.datasets.commercial_customer_status_90d.v1
--       resolved DATABRICKS binding: sales.datasets.commercial_customer_status_90d (view)
--
-- Enterprise analytics runs on Snowflake; the Sales status view runs on Databricks. The Databricks
-- object is surfaced into the enterprise Snowflake environment via Delta Sharing
-- (analytics.sales_share.commercial_customer_status_90d). No single warehouse spans both inputs —
-- the REGISTRY is what unifies them, and resolve_binding is what returns the correct physical
-- object per engine.
-- =========================================================================
CREATE OR REPLACE VIEW analytics.enterprise.customer_arpac_components_90d AS
WITH recognized_revenue AS (
    -- finance.logic.recognize_revenue.v1 via the certified Snowflake UDF (nets refunds, USD)
    SELECT
        customer_id,
        SUM(recognized_revenue_usd) AS net_recognized_revenue_90d_usd
    FROM TABLE(FINANCE.LOGIC.RECOGNIZE_REVENUE(
        DATEADD(day, -90, CURRENT_DATE()),
        CURRENT_DATE()
    ))
    GROUP BY customer_id
),
active_status AS (
    -- sales.datasets.commercial_customer_status_90d.v1 — resolved Databricks binding, shared into
    -- Snowflake via Delta Sharing (the cross-engine hop the registry records).
    SELECT
        customer_id,
        reporting_date,
        is_active_commercial_90d
    FROM analytics.sales_share.commercial_customer_status_90d
    WHERE reporting_date = CURRENT_DATE()
)
SELECT
    s.customer_id,
    s.reporting_date,
    COALESCE(rr.net_recognized_revenue_90d_usd, 0) AS net_recognized_revenue_90d_usd,
    s.is_active_commercial_90d
FROM active_status AS s
LEFT JOIN recognized_revenue AS rr
  ON rr.customer_id = s.customer_id;
