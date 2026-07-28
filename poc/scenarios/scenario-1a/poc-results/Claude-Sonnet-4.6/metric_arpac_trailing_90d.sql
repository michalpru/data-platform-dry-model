-- =============================================================================
-- Metric: arpac_trailing_90d
-- Average Revenue Per Active Customer — Trailing 90-Day Window
-- Target platform: Snowflake SQL
-- Output schema:  shared   (same schema as source datasets)
--
-- REUSE SUMMARY
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. shared.dim_customers.is_active  [REUSED — no change]
--      Active-customer definition from the existing customer dimension.
--      Flag semantics: customer placed ≥ 1 order in the last 12 months.
--      This is the same definition used in other executive dashboards, so
--      the ARPAC denominator is aligned with those reports.
--
-- 2. shared.fact_invoices  [REUSED — filtered, not duplicated]
--      Source of gross invoice amounts. Only POSTED invoices are included
--      (DRAFT and VOID are excluded), consistent with revenue-recognition
--      practice implied by the status vocabulary in the DDL.
--
-- 3. shared.fact_refunds  [REUSED — filtered, not duplicated]
--      Source of credit-note/refund adjustments. Per the DDL comment
--      ("net recognized revenue must subtract approved refunds/credit notes
--      from gross invoice amounts"), only APPROVED refunds are subtracted.
--      PENDING and REJECTED refunds are excluded.
--
-- CURRENCY ASSUMPTION
-- ─────────────────────────────────────────────────────────────────────────────
-- fact_invoices documents that invoices are NOT necessarily in USD.
-- No FX-rate lookup table is present in this workspace, so this
-- implementation conservatively includes only rows where currency_code = 'USD'.
-- To support multi-currency revenue, join an FX-rates table and convert
-- each amount to USD before aggregating; that table is not available here.
--
-- METRIC WINDOW
-- ─────────────────────────────────────────────────────────────────────────────
-- Trailing 90 days: invoice_date in [CURRENT_DATE - 90, CURRENT_DATE].
-- Refunds are scoped to invoices within that same window (i.e., approved
-- refunds on invoices that were posted in the trailing period), so the
-- net revenue figure reflects the period's own transactions.
-- =============================================================================

WITH

-- ── 1. Active customer count ────────────────────────────────────────────────
-- Reuses dim_customers.is_active (existing executive-dashboard definition).
active_customers AS (
    SELECT
        COUNT(*)  AS active_customer_count
    FROM shared.dim_customers
    WHERE is_active = TRUE
),

-- ── 2. Gross revenue: POSTED invoices in the trailing 90-day window ─────────
-- Reuses fact_invoices; filters to POSTED status and USD currency.
gross_revenue AS (
    SELECT
        COALESCE(SUM(invoice_amount), 0)  AS gross_revenue_usd
    FROM shared.fact_invoices
    WHERE invoice_status = 'POSTED'
      AND invoice_date   >= DATEADD('day', -90, CURRENT_DATE)
      AND currency_code  = 'USD'
),

-- ── 3. Approved refunds on invoices in the trailing 90-day window ───────────
-- Reuses fact_refunds; joins to fact_invoices to scope refunds to the
-- same trailing window and to the same USD-only currency filter.
approved_refunds AS (
    SELECT
        COALESCE(SUM(fr.refund_amount), 0)  AS total_refunds_usd
    FROM shared.fact_refunds   fr
    INNER JOIN shared.fact_invoices fi
        ON fr.invoice_id    = fi.invoice_id
    WHERE fr.refund_status = 'APPROVED'
      AND fi.invoice_date  >= DATEADD('day', -90, CURRENT_DATE)
      AND fr.currency_code = 'USD'
),

-- ── 4. Net recognized revenue ────────────────────────────────────────────────
net_revenue AS (
    SELECT
        g.gross_revenue_usd - r.total_refunds_usd  AS net_revenue_usd
    FROM       gross_revenue    g
    CROSS JOIN approved_refunds r
)

-- ── 5. ARPAC ─────────────────────────────────────────────────────────────────
SELECT
    CURRENT_DATE                                          AS metric_date,
    DATEADD('day', -90, CURRENT_DATE)                    AS window_start,
    CURRENT_DATE                                         AS window_end,
    nr.net_revenue_usd,
    ac.active_customer_count,
    CASE
        WHEN ac.active_customer_count = 0 THEN NULL
        ELSE ROUND(nr.net_revenue_usd / ac.active_customer_count, 2)
    END                                                  AS arpac_usd
FROM       net_revenue       nr
CROSS JOIN active_customers  ac
;
