-- arpac_90d.sql — SCENARIO 1B expected Copilot output (illustrative, ANSI SQL)
-- =========================================================================
-- Copilot now sees the domain repos and REUSES the most similar-looking artifacts it finds:
--   * Revenue -> finance.invoice_revenue           (LEGACY/RETIRED: skips refunds, invoice-date based)
--   * Active  -> marketing.logic.active_customer    (marketing portal-login rule, NOT enterprise 90d)
-- Both are discoverable and look reusable, but neither is the authoritative definition.
-- Similarity and availability are NOT business authority — the core Pattern-2 failure.
--
-- (The active-customer set is produced by the marketing Python function and materialised here as
--  marketing_active_customers_90d for the join; see workspace/marketing-domain/.)
-- =========================================================================
SELECT
    SUM(r.invoice_revenue_usd)
        / NULLIF(COUNT(DISTINCT a.customer_id), 0) AS arpac_90d
FROM finance.invoice_revenue AS r
JOIN marketing_active_customers_90d AS a
  ON a.customer_id = r.customer_id
WHERE r.revenue_date >= CURRENT_DATE - INTERVAL '90' DAY;
