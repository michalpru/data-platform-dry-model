-- arpac_90d.sql — SCENARIO 1B expected Copilot output (illustrative, Snowflake SQL)
-- =========================================================================
-- The enterprise-analytics engineer works in Snowflake and REUSES the most similar-looking
-- artifacts discovered across the workspace:
--   * Revenue -> finance.invoice_revenue           (Snowflake view; LEGACY/RETIRED: skips refunds)
--   * Active  -> marketing.logic.active_customer    (Databricks PySpark; marketing login rule)
-- Two problems, both invisible to similarity search:
--   1. Authority: invoice_revenue is retired and the marketing rule is not enterprise — neither
--      is authoritative, yet both look reusable (the core Pattern-2 failure).
--   2. Cross-engine: the active-customer set is produced on DATABRICKS (PySpark), but the revenue
--      view is on SNOWFLAKE. To join them the engineer must export the Databricks output and land
--      it in Snowflake as marketing_active_customers_90d — a brittle cross-warehouse hop that no
--      workspace search flags. (See workspace/marketing-domain/.)
-- =========================================================================
SELECT
    SUM(r.invoice_revenue_usd)
        / NULLIF(COUNT(DISTINCT a.customer_id), 0) AS arpac_90d
FROM finance.invoice_revenue AS r
JOIN marketing_active_customers_90d AS a   -- Databricks PySpark output, copied into Snowflake
  ON a.customer_id = r.customer_id
WHERE r.revenue_date >= DATEADD(day, -90, CURRENT_DATE());
