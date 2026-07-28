-- =============================================================================
-- Metric: arpac_trailing_90d
-- Average Revenue Per Active Customer — trailing 90-day window
-- Engine:  Snowflake SQL (shared DWH dialect)
-- Schema:  shared  (same schema as the source datasets)
--
-- Definition:  ARPAC = net recognized revenue in USD  /  number of active customers
--
-- -----------------------------------------------------------------------------
-- REUSE SUMMARY (only assets present in the workspace were used)
-- -----------------------------------------------------------------------------
--   1. shared.dim_customers.is_active   [REUSED as-is]
--        The active-customer definition. Per the DDL comment this flag means
--        "placed >= 1 order in the last 12 months" and is the same flag other
--        executive dashboards drive off, so the ARPAC denominator is aligned
--        with those reports by construction (no new definition invented).
--
--   2. shared.fact_invoices             [REUSED — filtered, not duplicated]
--        Gross recognized revenue. Only POSTED invoices are recognized;
--        DRAFT and VOID are excluded per the status vocabulary in the DDL.
--
--   3. shared.fact_refunds              [REUSED — filtered, not duplicated]
--        Refund / credit-note adjustments. The DDL comment states that
--        "net recognized revenue must subtract approved refunds/credit notes
--        from gross invoice amounts", so only APPROVED refunds are netted;
--        PENDING and REJECTED refunds are excluded. Refunds are joined back to
--        fact_invoices so they are scoped to the same trailing-90-day cohort.
--
-- -----------------------------------------------------------------------------
-- CURRENCY (known limitation — surfaced, not hidden)
-- -----------------------------------------------------------------------------
--   fact_invoices and fact_refunds are NOT necessarily in USD, and this
--   workspace contains NO FX / exchange-rate table. Mixed-currency amounts
--   therefore CANNOT be summed as if they were USD without overstating or
--   understating the result.
--
--   This implementation conservatively restricts revenue to rows where
--   currency_code = 'USD' so the published number is a defensible USD figure,
--   and it emits a coverage diagnostic (usd_invoice_coverage_pct) that reports
--   how much POSTED invoice volume was EXCLUDED because it was non-USD. If that
--   coverage is materially below 100%, the metric is incomplete and an FX-rate
--   table must be added (see "Extending to multi-currency" at the bottom).
--
-- -----------------------------------------------------------------------------
-- WINDOW
-- -----------------------------------------------------------------------------
--   Trailing 90 days: transaction date in [CURRENT_DATE - 90, CURRENT_DATE].
--   The numerator (revenue) is windowed; the denominator (active customers)
--   reuses the dashboard is_active flag verbatim and is intentionally NOT
--   re-windowed, so it stays comparable to the other executive dashboards.
-- =============================================================================

WITH

-- 1. Active-customer count -----------------------------------------------------
--    Reuses dim_customers.is_active — the definition already used by other
--    executive dashboards. No local re-definition of "active".
active_customers AS (
    SELECT
        COUNT(*) AS active_customer_count
    FROM shared.dim_customers
    WHERE is_active = TRUE
),

-- 2. Gross recognized revenue (USD), trailing 90 days --------------------------
--    Reuses fact_invoices; POSTED only; USD only (see CURRENCY note).
gross_revenue AS (
    SELECT
        COALESCE(SUM(invoice_amount), 0) AS gross_revenue_usd
    FROM shared.fact_invoices
    WHERE invoice_status = 'POSTED'
      AND invoice_date  >= DATEADD('day', -90, CURRENT_DATE)
      AND currency_code  = 'USD'
),

-- 3. Approved refunds (USD) on invoices in the same window ---------------------
--    Reuses fact_refunds; APPROVED only; joined to fact_invoices so refunds
--    belong to the same trailing-90-day POSTED-invoice cohort as the numerator.
approved_refunds AS (
    SELECT
        COALESCE(SUM(fr.refund_amount), 0) AS refunds_usd
    FROM shared.fact_refunds fr
    INNER JOIN shared.fact_invoices fi
        ON fi.invoice_id = fr.invoice_id
    WHERE fr.refund_status = 'APPROVED'
      AND fr.currency_code = 'USD'
      AND fi.invoice_status = 'POSTED'
      AND fi.invoice_date  >= DATEADD('day', -90, CURRENT_DATE)
),

-- 4. Currency-coverage diagnostic ---------------------------------------------
--    Reports what fraction of POSTED trailing-90-day invoice value is USD.
--    A value below 100% means non-USD revenue was dropped and the metric is
--    incomplete until an FX table is added.
currency_coverage AS (
    SELECT
        COALESCE(SUM(CASE WHEN currency_code = 'USD' THEN invoice_amount END), 0) AS usd_invoice_amount,
        COALESCE(SUM(invoice_amount), 0)                                          AS all_invoice_amount
    FROM shared.fact_invoices
    WHERE invoice_status = 'POSTED'
      AND invoice_date  >= DATEADD('day', -90, CURRENT_DATE)
)

-- 5. ARPAC ---------------------------------------------------------------------
SELECT
    CURRENT_DATE                                     AS metric_date,
    DATEADD('day', -90, CURRENT_DATE)                AS window_start,
    CURRENT_DATE                                     AS window_end,
    gr.gross_revenue_usd,
    ar.refunds_usd,
    (gr.gross_revenue_usd - ar.refunds_usd)          AS net_recognized_revenue_usd,
    ac.active_customer_count,
    CASE
        WHEN ac.active_customer_count = 0 THEN NULL
        ELSE ROUND((gr.gross_revenue_usd - ar.refunds_usd) / ac.active_customer_count, 2)
    END                                              AS arpac_usd,
    -- Data-quality signal: 100.00 means all trailing-90-day POSTED revenue was USD.
    CASE
        WHEN cc.all_invoice_amount = 0 THEN NULL
        ELSE ROUND(100.0 * cc.usd_invoice_amount / cc.all_invoice_amount, 2)
    END                                              AS usd_invoice_coverage_pct
FROM       gross_revenue     gr
CROSS JOIN approved_refunds  ar
CROSS JOIN active_customers  ac
CROSS JOIN currency_coverage cc
;

-- =============================================================================
-- Extending to multi-currency (requires an asset NOT present in this workspace)
-- -----------------------------------------------------------------------------
-- Once a shared FX-rate table (e.g. shared.fx_rates(currency_code, rate_date,
-- usd_rate)) exists, replace the "currency_code = 'USD'" filters with a join
-- that converts each amount to USD, e.g.:
--
--     SUM(fi.invoice_amount * fx.usd_rate)
--     ...
--     JOIN shared.fx_rates fx
--       ON fx.currency_code = fi.currency_code
--      AND fx.rate_date     = fi.invoice_date
--
-- and apply the same conversion to fact_refunds. No such table is available
-- here, so it is intentionally left out rather than fabricated.
-- =============================================================================
