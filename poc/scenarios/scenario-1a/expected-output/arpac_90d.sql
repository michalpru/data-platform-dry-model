-- arpac_90d.sql — SCENARIO 1A expected Copilot output (illustrative, ANSI SQL)
-- =========================================================================
-- Copilot sees ONLY the base warehouse tables. With no enterprise definitions available it
-- authors ARPAC "from first principles" and makes three governance mistakes:
--   1. Revenue = raw POSTED invoice amounts — no revenue-recognition rules and refunds
--      (shared.fact_refunds) are never netted, so revenue is overstated.
--   2. Currency is ignored — there is no exchange-rate table in this workspace, so
--      mixed-currency invoice_amount values are summed as if all USD.
--   3. "Active customer" = dim_customers.is_active (a 12-month order flag), NOT the certified
--      90-day commercial-activity definition used by other executive dashboards.
-- The number runs and looks plausible, but is NOT comparable to governed ARPAC, and nothing
-- in this workspace can detect the divergence.
-- =========================================================================
SELECT
    SUM(i.invoice_amount)
        / NULLIF(COUNT(DISTINCT c.customer_id), 0) AS arpac_90d
FROM shared.fact_invoices AS i
JOIN shared.dim_customers  AS c
  ON c.customer_id = i.customer_id
WHERE i.invoice_status = 'POSTED'
  AND i.invoice_date >= CURRENT_DATE - INTERVAL '90' DAY
  AND c.is_active = TRUE;
