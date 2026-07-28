-- arpac_90d.sql — SCENARIO 2 expected output (registry-aware; Snowflake SQL)
-- =========================================================================
-- The enterprise-analytics domain runs on Snowflake. The DRY Reuse agent resolved certified
-- artifacts from the registry BEFORE authoring, and resolve_binding returned the SNOWFLAKE
-- binding of each component (native path — no cross-engine hop):
--   * net recognized revenue -> finance.metrics.net_recognized_revenue.v1
--       (built on finance.logic.recognize_revenue.v1 — recognition rules + refund netting +
--        currency normalization; Snowflake UDF analytics.finance.fn_recognize_revenue)
--   * active customer        -> enterprise.metrics.active_customer.v1
--       (the enterprise 90-day commercial-activity definition, owner: data-governance)
--
-- Only the ratio itself is new. It is authored in the consumer's single dialect (Snowflake).
-- Reuse is not limited to raw SQL: recognize_revenue is one certified identity with two Snowflake
-- bindings — the native UDF above and a dbt macro (dry_finance_macros.recognize_revenue). A dbt
-- model would `{{ recognize_revenue(...) }}` and reuse the exact same governed logic. dbt gives
-- reuse inside dbt; the registry records that the macro and the UDF are the same certified capability.
-- =========================================================================
WITH recognized_revenue AS (
    -- net_recognized_revenue.v1 via the certified Snowflake UDF (nets refunds, normalizes to USD)
    SELECT
        customer_id,
        SUM(recognized_revenue_usd) AS net_recognized_revenue_usd
    FROM TABLE(analytics.finance.fn_recognize_revenue(
        DATEADD(day, -90, CURRENT_DATE()),
        CURRENT_DATE()
    ))
    GROUP BY customer_id
),
active_customers AS (
    -- enterprise.metrics.active_customer.v1 — resolved Snowflake binding
    SELECT customer_id
    FROM analytics.enterprise.active_customer_90d
    WHERE reporting_date = CURRENT_DATE()
      AND is_active_commercial_90d = TRUE
)
SELECT
    SUM(rr.net_recognized_revenue_usd)
        / NULLIF(COUNT(DISTINCT ac.customer_id), 0) AS arpac_90d_usd
FROM recognized_revenue AS rr
JOIN active_customers   AS ac
  ON ac.customer_id = rr.customer_id;
