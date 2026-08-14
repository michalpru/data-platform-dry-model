-- Snowflake SQL
-- arpac_trailing_90d.sql
--
-- REUSE INVENTORY
-- ┌──────────────────────────────────────────────┬─────────────────────────────────────────────────────┐
-- │ Artifact reused                              │ What it contributes                                 │
-- ├──────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
-- │ finance.invoice_revenue  (view)              │ POSTED invoices already FX-converted to USD;        │
-- │                                              │ avoids re-implementing the exchange-rate join and   │
-- │                                              │ invoice-status filter.                              │
-- ├──────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
-- │ finance.dim_exchange_rates  (table)          │ Reused for refund FX conversion using the same join │
-- │                                              │ pattern as invoice_revenue.  normalize_currency()   │
-- │                                              │ is not used because refund netting requires a       │
-- │                                              │ set-based join rather than a scalar/row UDF call.   │
-- ├──────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
-- │ marketing.active_customer  (Python / Spark)  │ Active-customer definition ported 1-for-1 to SQL:   │
-- │  active_customer.py                          │   application_name = 'Marketing Portal'             │
-- │                                              │   trailing-N-day login window (N = 90)              │
-- │                                              │ Ensures the denominator aligns with marketing exec  │
-- │                                              │ dashboards.  dim_customers.is_active was            │
-- │                                              │ intentionally NOT used — it is a 12-month order     │
-- │                                              │ flag, not the 90-day login-based definition.        │
-- └──────────────────────────────────────────────┴─────────────────────────────────────────────────────┘
--
-- FORMULA
--   ARPAC = net_revenue_usd / active_customer_count
--
--   net_revenue_usd  = SUM(invoice_revenue_usd for active customers)
--                    - SUM(APPROVED refunds in USD for those invoices)
--                    both within [as_of_date - 90 days, as_of_date]
--
--   active_customers = DISTINCT customers with a Marketing Portal login
--                      in [as_of_date - 90 days, as_of_date]
--
-- DEPLOYMENT NOTE
--   This metric spans the finance and marketing domains; deploy to an executive
--   (or cross-domain analytics) schema.  The function body references:
--     marketing.customer_logins   — expected columns: customer_id, login_timestamp, application_name
--     finance.invoice_revenue     — view defined in finance-domain/finance/datasets/
--     finance.dim_exchange_rates  — table defined in finance-domain/finance/datasets/
--     shared.fact_refunds         — table defined in dwh/shared/datasets/

CREATE OR REPLACE FUNCTION executive.arpac_trailing_90d(as_of_date DATE)
RETURNS TABLE (
    as_of_date            DATE,
    trailing_days         NUMBER,
    active_customer_count NUMBER,
    gross_revenue_usd     NUMBER(18,2),
    total_refunds_usd     NUMBER(18,2),
    net_revenue_usd       NUMBER(18,2),
    arpac_usd             NUMBER(18,2)
)
AS
$$
    WITH
    -- Denominator: exact SQL port of marketing/logic/active_customer.py.
    -- Criteria preserved: application_name = 'Marketing Portal', window = trailing 90 days.
    -- Port note: PySpark compares timestamp <= DateType by casting the date to midnight (00:00:00),
    --   so `<= as_of_date` here reproduces that inclusive-date upper-bound exactly.
    active_customers AS (
        SELECT DISTINCT customer_id
        FROM marketing.customer_logins
        WHERE application_name = 'Marketing Portal'
          AND login_timestamp  >= DATEADD('day', -90, as_of_date)
          AND login_timestamp  <= as_of_date
    ),

    -- Numerator (gross): revenue from active customers within the 90-day window.
    -- Reuses finance.invoice_revenue, which already applies the POSTED filter and USD conversion.
    active_gross AS (
        SELECT
            ir.invoice_id,
            ir.invoice_revenue_usd
        FROM finance.invoice_revenue  AS ir
        INNER JOIN active_customers   AS ac ON ac.customer_id = ir.customer_id
        WHERE ir.revenue_date >= DATEADD('day', -90, as_of_date)
          AND ir.revenue_date <= as_of_date
    ),

    -- Deductions: APPROVED refunds on active-customer invoices within the window, converted to USD.
    -- Uses the same FX join pattern as finance.invoice_revenue (from_currency → USD on event date).
    active_refunds AS (
        SELECT
            r.invoice_id,
            ROUND(r.refund_amount * fx.exchange_rate, 2) AS refund_usd
        FROM shared.fact_refunds              AS r
        INNER JOIN finance.dim_exchange_rates AS fx
          ON  fx.from_currency = r.currency_code
          AND fx.to_currency   = 'USD'
          AND fx.rate_date     = r.refund_date
        INNER JOIN active_gross               AS ag ON ag.invoice_id = r.invoice_id
        WHERE r.refund_status = 'APPROVED'
          AND r.refund_date  >= DATEADD('day', -90, as_of_date)
          AND r.refund_date  <= as_of_date
    ),

    -- Aggregate refunds per invoice to avoid double-counting when one invoice has multiple refunds.
    refunds_by_invoice AS (
        SELECT invoice_id, SUM(refund_usd) AS invoice_refund_usd
        FROM   active_refunds
        GROUP  BY invoice_id
    ),

    revenue_net AS (
        SELECT
            COALESCE(SUM(ag.invoice_revenue_usd), 0) AS gross_rev,
            COALESCE(SUM(ri.invoice_refund_usd),  0) AS total_ref
        FROM      active_gross        AS ag
        LEFT JOIN refunds_by_invoice  AS ri ON ri.invoice_id = ag.invoice_id
    )

    SELECT
        as_of_date,
        90                                                                AS trailing_days,
        (SELECT COUNT(*) FROM active_customers)                           AS active_customer_count,
        rn.gross_rev                                                      AS gross_revenue_usd,
        rn.total_ref                                                      AS total_refunds_usd,
        rn.gross_rev - rn.total_ref                                       AS net_revenue_usd,
        ROUND(
            (rn.gross_rev - rn.total_ref)
            / NULLIF((SELECT COUNT(*) FROM active_customers), 0),
            2
        )                                                                 AS arpac_usd
    FROM revenue_net AS rn
$$;

-- Convenience view: binds as_of_date = CURRENT_DATE for dashboards that poll daily.
CREATE OR REPLACE VIEW executive.arpac_trailing_90d_current AS
    SELECT * FROM TABLE(executive.arpac_trailing_90d(CURRENT_DATE));
