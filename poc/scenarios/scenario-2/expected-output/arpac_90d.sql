-- arpac_90d.sql — SCENARIO 2 expected output (registry-aware, portable ANSI SQL)
-- =========================================================================
-- The DRY Reuse agent resolved certified artifacts from the registry BEFORE authoring:
--   * net recognized revenue -> finance.metrics.net_recognized_revenue.v1
--       (built on finance.logic.recognize_revenue.v1 — recognition rules + refund netting +
--        currency normalization, owner: finance-analytics, lifecycle: certified)
--   * active customer        -> enterprise.metrics.active_customer.v1
--       (the enterprise 90-day commercial-activity definition, owner: data-governance)
--
-- Only the ratio itself is new. The referenced relations below are LOGICAL identities; the
-- physical objects come from resolve_binding for the target runtime/dialect. This SQL is ANSI
-- and portable — the registry maps it to the Snowflake / Databricks / Spark binding.
-- =========================================================================
WITH recognized_revenue AS (
    -- finance.metrics.net_recognized_revenue.v1  (certified; nets refunds, normalizes to USD)
    SELECT
        customer_id,
        SUM(recognized_revenue_usd) AS net_recognized_revenue_usd
    FROM finance.net_recognized_revenue_90d      -- resolved binding of net_recognized_revenue.v1
    GROUP BY customer_id
),
active_customers AS (
    -- enterprise.metrics.active_customer.v1  (certified; enterprise 90-day commercial activity)
    SELECT customer_id
    FROM enterprise.active_customer_90d          -- resolved binding of active_customer.v1
    WHERE reporting_date = CURRENT_DATE
      AND is_active_commercial_90d = TRUE
)
SELECT
    SUM(rr.net_recognized_revenue_usd)
        / NULLIF(COUNT(DISTINCT ac.customer_id), 0) AS arpac_90d_usd
FROM recognized_revenue AS rr
JOIN active_customers   AS ac
  ON ac.customer_id = rr.customer_id;
