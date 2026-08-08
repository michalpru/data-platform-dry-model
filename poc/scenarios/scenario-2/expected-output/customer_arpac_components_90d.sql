-- customer_arpac_components_90d.sql — SCENARIO 2 generated output (enterprise components dataset; Snowflake SQL)
-- =========================================================================
-- Registry FQN: enterprise.datasets.customer_arpac_components_90d.v1
-- Grain:        (customer_id, reporting_date)   — a genuine panel across reporting dates
--
-- One of the two artifacts the DRY Reuse agent AUTHORS in scenario 2 — the small, missing
-- composition that joins two already-certified inputs. Nothing here re-implements a
-- revenue-recognition rule, a netting rule, a currency rule, or an activity window; each of those
-- is a resolved, certified binding.
--
-- CROSS-ENGINE COMPOSITION (the point of this scenario):
--   * net recognized revenue -> finance.logic.recognize_revenue.v1
--       resolved SNOWFLAKE binding: FINANCE.LOGIC.RECOGNIZE_REVENUE (native table UDF)
--       signature confirmed from the binding source (not guessed):
--         RECOGNIZE_REVENUE(P_START_DATE DATE, P_END_DATE DATE)
--         RETURNS TABLE(CUSTOMER_ID, ..., RECOGNIZED_REVENUE_USD)
--   * active-customer status  -> sales.datasets.commercial_customer_status_90d.v1
--       resolved DATABRICKS binding: sales.datasets.commercial_customer_status_90d (view)
--
-- CROSS-ENGINE GAP — flagged, NOT fabricated:
--   Enterprise analytics runs on Snowflake; the Sales status view runs on Databricks.
--   resolve_binding(sales.datasets.commercial_customer_status_90d.v1, runtime=warehouse) returns
--   NO Snowflake binding. This view references the resolved Databricks binding under the explicit
--   precondition that it is made reachable from Snowflake once a target-engine binding is
--   provisioned (portable-SQL framework, or a shared/federated view registered as an ADDITIONAL
--   binding on the artifact). No bridge object is invented here — provisioning it is an integration
--   requirement, out of scope for this PoC.
-- =========================================================================
CREATE OR REPLACE VIEW analytics.enterprise.customer_arpac_components_90d AS
WITH active_status AS (
    -- sales.datasets.commercial_customer_status_90d.v1 — resolved DATABRICKS binding.
    -- [CROSS-ENGINE PRECONDITION] assumes reachable from Snowflake once a binding is provisioned;
    -- referenced at its resolved name, no bridge object fabricated. Grain: (customer_id, reporting_date).
    SELECT
        customer_id,
        reporting_date,
        is_active_commercial_90d
    FROM sales.datasets.commercial_customer_status_90d
),
revenue_panel AS (
    -- finance.logic.recognize_revenue.v1 via the certified Snowflake UDF, windowed to each
    -- reporting_date's trailing-90-day span. Output already net of refunds and normalized to USD.
    -- RECOGNIZED_REVENUE_USD confirmed from the binding source.
    SELECT
        d.reporting_date,
        rr.CUSTOMER_ID                 AS customer_id,
        SUM(rr.RECOGNIZED_REVENUE_USD) AS net_recognized_revenue_90d_usd
    FROM (SELECT DISTINCT reporting_date FROM active_status) AS d,
         TABLE(FINANCE.LOGIC.RECOGNIZE_REVENUE(
             DATEADD(day, -89, d.reporting_date),   -- trailing 90-day inclusive window
             d.reporting_date
         )) AS rr
    GROUP BY d.reporting_date, rr.CUSTOMER_ID
)
SELECT
    s.customer_id,
    s.reporting_date,
    COALESCE(rp.net_recognized_revenue_90d_usd, 0) AS net_recognized_revenue_90d_usd,
    s.is_active_commercial_90d
FROM active_status AS s
LEFT JOIN revenue_panel AS rp
  ON rp.customer_id    = s.customer_id
 AND rp.reporting_date = s.reporting_date;
