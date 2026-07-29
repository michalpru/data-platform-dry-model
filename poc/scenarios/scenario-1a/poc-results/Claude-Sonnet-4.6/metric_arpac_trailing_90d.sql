-- =============================================================================
-- Metric: ARPAC – Average Revenue per Active Customer (Trailing 90 Days)
-- Purpose: Executive reporting
-- Dialect: Snowflake SQL
--
-- Definition:
--   ARPAC = Net Recognized Revenue (USD) / Active Customers
--
-- Reused definitions (see README.md for full reuse inventory):
--   • shared.dim_customers.is_active  — active-customer flag already used in
--     other executive dashboards; defined as "placed >= 1 order in the last
--     12 months" (comment in dim_customers DDL).
--   • shared.fact_invoices            — canonical invoice fact table.
--   • shared.fact_refunds             — canonical refund fact table.
--
-- Assumptions / constraints:
--   • Only USD-denominated invoices and refunds are included.  No FX-conversion
--     table is available in the workspace; multi-currency rows are excluded and
--     should be addressed in a follow-up if they are material.
--   • "Net recognized revenue" = POSTED invoices minus APPROVED refunds whose
--     transaction date falls within the trailing-90-day window.
--   • Refund window is based on refund_date (when the refund was approved),
--     not on the originating invoice_date.
--   • Returns NULL for ARPAC when there are no active customers (avoids
--     divide-by-zero).
-- =============================================================================

WITH

-- ── 1. Trailing-90-day window boundary ───────────────────────────────────────
window_boundary AS (
    SELECT
        DATEADD(DAY, -90, CURRENT_DATE) AS window_start,
        CURRENT_DATE                    AS window_end
),

-- ── 2. Gross revenue: POSTED invoices in USD within the 90-day window ────────
--   Reuses: shared.fact_invoices
gross_revenue AS (
    SELECT
        COALESCE(SUM(i.invoice_amount), 0) AS total_gross_revenue_usd
    FROM shared.fact_invoices  AS i
    CROSS JOIN window_boundary AS w
    WHERE i.invoice_status = 'POSTED'
      AND i.currency_code  = 'USD'
      AND i.invoice_date  >= w.window_start
      AND i.invoice_date  <= w.window_end
),

-- ── 3. Approved refunds in USD within the 90-day window ──────────────────────
--   Reuses: shared.fact_refunds
approved_refunds AS (
    SELECT
        COALESCE(SUM(r.refund_amount), 0) AS total_refunds_usd
    FROM shared.fact_refunds   AS r
    CROSS JOIN window_boundary AS w
    WHERE r.refund_status = 'APPROVED'
      AND r.currency_code = 'USD'
      AND r.refund_date  >= w.window_start
      AND r.refund_date  <= w.window_end
),

-- ── 4. Net recognized revenue ─────────────────────────────────────────────────
net_revenue AS (
    SELECT
        g.total_gross_revenue_usd - r.total_refunds_usd AS total_net_revenue_usd
    FROM gross_revenue   g
    CROSS JOIN approved_refunds r
),

-- ── 5. Active-customer count ──────────────────────────────────────────────────
--   Reuses: shared.dim_customers.is_active
--   Definition (from DDL): placed >= 1 order in the last 12 months.
--   This is the same definition used in other executive dashboards.
active_customers AS (
    SELECT
        COUNT(customer_id) AS total_active_customers
    FROM shared.dim_customers
    WHERE is_active = TRUE
)

-- ── 6. Final ARPAC output ─────────────────────────────────────────────────────
SELECT
    w.window_start                                      AS window_start_date,
    w.window_end                                        AS window_end_date,
    nr.total_net_revenue_usd,
    ac.total_active_customers,
    CASE
        WHEN ac.total_active_customers = 0 THEN NULL
        ELSE ROUND(
                 nr.total_net_revenue_usd / ac.total_active_customers,
                 2
             )
    END                                                 AS arpac_usd
FROM net_revenue     nr
CROSS JOIN active_customers ac
CROSS JOIN window_boundary  w;
