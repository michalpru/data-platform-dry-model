-- =============================================================================
-- Metric : arpac_trailing_90d
-- Schema : metrics
-- Engine : Snowflake
--
-- Business Definition
-- -------------------
--   ARPAC (Average Revenue Per Active Customer) — trailing 90 days
--
--   ARPAC = Net Recognized Revenue (USD) ÷ Active Customer Count
--
--   Net Recognized Revenue:
--     Sum of POSTED invoice revenue converted to USD
--     minus sum of APPROVED refunds converted to USD
--     within the trailing 90-day window ending on CURRENT_DATE (inclusive).
--
--   Active Customers:
--     Distinct customers who logged in to the "Marketing Portal" application
--     within the same trailing 90-day window ending on CURRENT_DATE.
--
-- Reuse Inventory
-- ---------------
-- [R1] finance.invoice_revenue  (VIEW — finance-domain/finance/datasets/invoice_revenue.sql)
--       Provides per-invoice FX-converted revenue in USD for POSTED invoices.
--       Reused directly — the join to finance.dim_exchange_rates, the 'POSTED'
--       status filter, and the ROUND(amount * rate, 2) rounding convention are
--       already encoded there. No duplication of that logic here.
--
-- [R2] finance.dim_exchange_rates  (TABLE — finance-domain/finance/datasets/dim_exchange_rates.sql)
--       Provides daily exchange rates keyed on (from_currency, to_currency, rate_date).
--       Reused for refund FX conversion, using the identical join pattern
--       already established by finance.invoice_revenue and finance.normalize_currency.
--
-- [R3] marketing/logic/active_customer.py  (PySpark logic — marketing-domain)
--       The authoritative active-customer definition used in executive dashboards.
--       Criteria translated verbatim into SQL:
--         • application_name = 'Marketing Portal'
--         • trailing_days    = 90  (the default in the function signature)
--         • window           = [as_of_date − 90 days, as_of_date] inclusive
--         • aggregation      = COUNT(DISTINCT customer_id)
--       Source table assumed: marketing.customer_logins
--         Required columns:  customer_id, login_timestamp, application_name
--
-- [R4] shared.fact_refunds  (TABLE — dwh/shared/datasets/fact_refunds.sql)
--       Shared DWH layer fact table for refunds.  Reused directly.
--
-- Assumptions
-- -----------
-- • marketing.customer_logins exists with columns matching active_customer.py.
-- • Exchange rates in finance.dim_exchange_rates are available for every
--   (currency, refund_date) pair that appears in fact_refunds.  Refund rows
--   with no matching rate are excluded by the INNER JOIN (same behaviour as
--   finance.invoice_revenue for invoices).
-- • The view is evaluated daily; as_of_date is always CURRENT_DATE.
-- =============================================================================

CREATE OR REPLACE VIEW metrics.arpac_trailing_90d AS

WITH

-- ---------------------------------------------------------------------------
-- [R1] Gross invoice revenue within the trailing 90-day window
--
-- Delegates entirely to finance.invoice_revenue, which already filters to
-- POSTED invoices and applies FX conversion to USD.  Only the date-window
-- predicate is added here.
--
-- Window: [CURRENT_DATE − 90 days, CURRENT_DATE] — matches the trailing_days=90
-- default in marketing/logic/active_customer.py (date_sub(as_of, 90)).
-- ---------------------------------------------------------------------------
total_gross_revenue AS (
    SELECT
        COALESCE(SUM(invoice_revenue_usd), 0) AS gross_revenue_usd
    FROM finance.invoice_revenue
    WHERE revenue_date >= DATEADD(day, -90, CURRENT_DATE)
      AND revenue_date <= CURRENT_DATE
),

-- ---------------------------------------------------------------------------
-- [R2 + R4] Total APPROVED refunds converted to USD
--
-- Applies the same FX join pattern as finance.invoice_revenue:
--   JOIN finance.dim_exchange_rates ON from_currency, to_currency='USD', rate_date
--   ROUND(amount * exchange_rate, 2)
-- Only 'APPROVED' refunds are recognised as reducing revenue.
-- ---------------------------------------------------------------------------
total_refunds AS (
    SELECT
        COALESCE(
            SUM(ROUND(r.refund_amount * fx.exchange_rate, 2)),
            0
        ) AS total_refunds_usd
    FROM shared.fact_refunds AS r
    JOIN finance.dim_exchange_rates AS fx
      ON  fx.from_currency = r.currency_code
      AND fx.to_currency   = 'USD'
      AND fx.rate_date     = r.refund_date
    WHERE r.refund_status = 'APPROVED'
      AND r.refund_date  >= DATEADD(day, -90, CURRENT_DATE)
      AND r.refund_date  <= CURRENT_DATE
),

-- ---------------------------------------------------------------------------
-- [R3] Active customer count — SQL translation of active_customer.py
--
-- Original Python (marketing/logic/active_customer.py):
--   as_of        = to_date(lit(as_of_date))
--   window_start = date_sub(as_of, trailing_days)          # as_of − 90
--   df.where(application_name == "Marketing Portal")
--     .where(login_timestamp >= window_start)
--     .where(login_timestamp <= as_of)
--     .select("customer_id").distinct()
--
-- SQL translation preserves every criterion exactly:
--   • application_name filter   → WHERE application_name = 'Marketing Portal'
--   • window_start              → DATEADD(day, -90, CURRENT_DATE)   (trailing_days=90)
--   • inclusive upper bound     → <= CURRENT_DATE
--   • .distinct()               → COUNT(DISTINCT customer_id)
-- ---------------------------------------------------------------------------
active_customers AS (
    SELECT
        COUNT(DISTINCT customer_id) AS active_customer_count
    FROM marketing.customer_logins
    WHERE application_name = 'Marketing Portal'
      AND CAST(login_timestamp AS DATE) >= DATEADD(day, -90, CURRENT_DATE)
      AND CAST(login_timestamp AS DATE) <= CURRENT_DATE
)

-- ---------------------------------------------------------------------------
-- Final ARPAC metric
--
-- All three scalar CTEs return exactly one row; CROSS JOINs are safe.
-- ARPAC is NULL (not zero) when there are no active customers to avoid
-- a misleading divide-by-zero result.
-- ---------------------------------------------------------------------------
SELECT
    CURRENT_DATE                                                       AS as_of_date,
    DATEADD(day, -90, CURRENT_DATE)                                    AS window_start_date,
    ac.active_customer_count,
    gr.gross_revenue_usd,
    tr.total_refunds_usd,
    gr.gross_revenue_usd - tr.total_refunds_usd                        AS net_revenue_usd,
    CASE
        WHEN ac.active_customer_count = 0 THEN NULL
        ELSE ROUND(
                 (gr.gross_revenue_usd - tr.total_refunds_usd)
                 / ac.active_customer_count,
             2)
    END                                                                AS arpac_usd

FROM total_gross_revenue AS gr
CROSS JOIN total_refunds  AS tr
CROSS JOIN active_customers AS ac;
