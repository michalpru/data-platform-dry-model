-- =============================================================================
-- Metric: ARPAC (Average Revenue per Active Customer) - Trailing 90 Days
-- Audience: Executive reporting
-- Dialect: Snowflake SQL
--
-- Definition:
--   ARPAC = Net recognized revenue (USD, trailing 90 days)
--           / Number of active customers
--
-- ---------------------------------------------------------------------------
-- REUSE (existing workspace artifacts, no re-implementation):
--   * shared.dim_customers.is_active
--       Reused as the ACTIVE-CUSTOMER definition. Per the dataset contract,
--       is_active = "placed >= 1 order in the last 12 months". This is the
--       same governed flag consumed by other executive dashboards, so the
--       denominator here is aligned with them by construction (we count the
--       flag, we do NOT recompute a new active definition).
--   * shared.fact_invoices
--       Reused as the source of recognized revenue. Recognition is scoped to
--       invoice_status = 'POSTED' (DRAFT / VOID are excluded).
--   * shared.fact_refunds
--       Reused as the source of revenue reversals. Only refund_status =
--       'APPROVED' reduces net revenue (PENDING / REJECTED are excluded).
--
-- ---------------------------------------------------------------------------
-- ASSUMPTIONS / DATA-QUALITY NOTES:
--   * "in USD": the workspace contains no shared FX-rate dataset or currency
--     conversion function, so amounts cannot be converted. Revenue and refunds
--     are therefore scoped to currency_code = 'USD'. If/when a shared FX-rate
--     dataset becomes available, replace the `currency_code = 'USD'` filters
--     with a join to it (single point of change, see marked lines below).
--   * The revenue window is trailing 90 days; the active-customer base uses the
--     existing 12-month is_active flag. This intentional window difference keeps
--     the denominator consistent with other executive dashboards, as required.
--   * Window is (as_of_date - 90 days, as_of_date], i.e. the most recent 90 days.
-- =============================================================================

CREATE OR REPLACE VIEW shared.metrics.arpac_trailing_90d AS
WITH params AS (
    -- Single source of truth for the reporting window within this metric.
    SELECT
        CURRENT_DATE                        AS as_of_date,
        DATEADD('day', -90, CURRENT_DATE)   AS window_start_date
),

recognized_revenue AS (
    -- Recognized gross revenue: POSTED invoices in the trailing-90-day window.
    SELECT COALESCE(SUM(i.invoice_amount), 0) AS gross_recognized_revenue_usd
    FROM shared.fact_invoices i
    CROSS JOIN params p
    WHERE i.invoice_status = 'POSTED'
      AND i.currency_code  = 'USD'          -- <-- replace with FX join when available
      AND i.invoice_date  >  p.window_start_date
      AND i.invoice_date  <= p.as_of_date
),

approved_refunds AS (
    -- Revenue reversals: APPROVED refunds in the trailing-90-day window.
    SELECT COALESCE(SUM(r.refund_amount), 0) AS refunds_usd
    FROM shared.fact_refunds r
    CROSS JOIN params p
    WHERE r.refund_status = 'APPROVED'
      AND r.currency_code = 'USD'           -- <-- replace with FX join when available
      AND r.refund_date  >  p.window_start_date
      AND r.refund_date  <= p.as_of_date
),

active_customers AS (
    -- Denominator: reuse the governed is_active flag (12-month definition
    -- aligned with existing executive dashboards). No recomputation here.
    SELECT COUNT(*) AS active_customer_count
    FROM shared.dim_customers
    WHERE is_active = TRUE
)

SELECT
    p.as_of_date,
    p.window_start_date,
    rr.gross_recognized_revenue_usd,
    ar.refunds_usd,
    rr.gross_recognized_revenue_usd - ar.refunds_usd            AS net_recognized_revenue_usd,
    ac.active_customer_count,
    CASE
        WHEN ac.active_customer_count = 0 THEN NULL              -- avoid divide-by-zero
        ELSE (rr.gross_recognized_revenue_usd - ar.refunds_usd)
             / ac.active_customer_count
    END                                                         AS arpac_trailing_90d_usd
FROM params p
CROSS JOIN recognized_revenue rr
CROSS JOIN approved_refunds   ar
CROSS JOIN active_customers   ac;

-- ---------------------------------------------------------------------------
-- Query the metric:
--   SELECT arpac_trailing_90d_usd FROM shared.metrics.arpac_trailing_90d;
--
-- Full breakdown (revenue, refunds, active base, ARPAC):
--   SELECT * FROM shared.metrics.arpac_trailing_90d;
-- ---------------------------------------------------------------------------
