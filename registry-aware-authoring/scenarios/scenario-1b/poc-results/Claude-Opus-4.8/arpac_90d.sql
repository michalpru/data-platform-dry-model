-- =====================================================================================
-- arpac_90d.sql  —  Trailing-90-day ARPAC (Average Revenue Per Active Customer)
-- Engine: Snowflake SQL
-- Author: Claude-Opus-4.8  (POC scenario 1B)
--
-- Metric definition (as requested):
--   ARPAC(90d) = NET recognized revenue in USD (trailing 90 days)
--                --------------------------------------------------
--                number of ACTIVE customers (trailing 90 days)
--
--   * NET recognized revenue = gross recognized revenue  −  approved refunds/credits, in USD.
--   * Active customer         = customer with commercial activity in the trailing 90-day window.
--
-- REUSE (see REUSE_NOTES.md for full rationale + governance caveats):
--   * finance.invoice_revenue      — REUSED for gross recognized revenue in USD (currency-normalized).
--   * shared.fact_refunds          — REUSED as the refund source to make revenue *net*.
--   * finance.normalize_currency   — REUSED (shared currency utility) to convert refunds to USD,
--                                    instead of re-implementing an FX join.
--   * shared.fact_invoices         — REUSED as the commercial-activity source for active customers.
--
-- IMPORTANT CAVEATS (governance signals NOT available from workspace search alone):
--   1. finance.invoice_revenue only sums POSTED invoices and SKIPS refunds. On its own it is
--      GROSS, not NET. This implementation nets out approved refunds to satisfy "net recognized
--      revenue". If a certified net-revenue metric exists in the registry, prefer it.
--   2. Active customer is defined here as "≥1 POSTED invoice in the window" (enterprise commercial
--      activity), derived from Snowflake data. The marketing rule
--      marketing.logic.active_customer was intentionally NOT reused: it is a marketing-portal-LOGIN
--      definition (not enterprise commercial activity), it runs on Databricks/PySpark (cross-engine),
--      and it depends on a customer_logins source that is not present in this workspace.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- Reusable metric view. Query it directly:  SELECT * FROM finance.arpac_90d;
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW finance.arpac_90d AS
WITH params AS (
    -- Single source of truth for the reporting window (trailing 90 days, inclusive).
    SELECT
        CURRENT_DATE()                              AS as_of_date,
        DATEADD(day, -90, CURRENT_DATE())           AS window_start
),

-- (1) GROSS recognized revenue in USD — REUSE of finance.invoice_revenue.
gross_revenue AS (
    SELECT
        COALESCE(SUM(r.invoice_revenue_usd), 0)     AS gross_revenue_usd
    FROM finance.invoice_revenue AS r
    CROSS JOIN params AS p
    WHERE r.revenue_date >= p.window_start
      AND r.revenue_date <= p.as_of_date
),

-- (2) Approved refunds in USD — REUSE of shared.fact_refunds + finance.normalize_currency.
--     normalize_currency is the shared FX utility; we reuse it instead of re-joining
--     dim_exchange_rates so currency conversion stays DRY and consistent.
refunds AS (
    SELECT
        COALESCE(SUM(nc.converted_amount), 0)       AS refunds_usd
    FROM shared.fact_refunds AS f
    CROSS JOIN params AS p,
    TABLE(finance.normalize_currency(
             f.refund_amount, f.currency_code, 'USD', f.refund_date
         )) AS nc
    WHERE f.refund_status = 'APPROVED'
      AND f.refund_date >= p.window_start
      AND f.refund_date <= p.as_of_date
),

-- (3) Active customers (trailing 90d) — enterprise COMMERCIAL-ACTIVITY definition,
--     derived from shared.fact_invoices (single-engine, queryable now).
active_customers AS (
    SELECT
        COUNT(DISTINCT i.customer_id)               AS active_customer_count
    FROM shared.fact_invoices AS i
    CROSS JOIN params AS p
    WHERE i.invoice_status = 'POSTED'
      AND i.invoice_date >= p.window_start
      AND i.invoice_date <= p.as_of_date
)

SELECT
    p.window_start                                                  AS window_start_date,
    p.as_of_date                                                    AS as_of_date,
    g.gross_revenue_usd,
    rf.refunds_usd,
    (g.gross_revenue_usd - rf.refunds_usd)                         AS net_recognized_revenue_usd,
    ac.active_customer_count,
    ROUND(
        (g.gross_revenue_usd - rf.refunds_usd)
        / NULLIF(ac.active_customer_count, 0)
    , 2)                                                           AS arpac_90d_usd
FROM params AS p
CROSS JOIN gross_revenue    AS g
CROSS JOIN refunds          AS rf
CROSS JOIN active_customers AS ac;


-- -------------------------------------------------------------------------------------
-- Executive-reporting query.
-- -------------------------------------------------------------------------------------
SELECT
    window_start_date,
    as_of_date,
    net_recognized_revenue_usd,
    active_customer_count,
    arpac_90d_usd
FROM finance.arpac_90d;
