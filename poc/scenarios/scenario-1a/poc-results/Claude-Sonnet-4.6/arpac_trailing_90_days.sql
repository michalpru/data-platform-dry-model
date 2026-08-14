-- Snowflake SQL — reusable executive metric view
-- Trailing-90-day Average Revenue per Active Customer (ARPAC)
--
-- Sources (workspace scope: poc/scenarios/scenario-1a/workspace only):
--   shared.dim_customers  — is_active flag (placed >= 1 order in last 12 months)
--   shared.fact_invoices  — POSTED invoice revenue
--   shared.fact_refunds   — APPROVED refund deductions (contra-revenue)
--
-- Reuse notes:
--   1. Active-customer definition: dim_customers.is_active = TRUE, the same flag
--      consumed by executive dashboards in this workspace.
--   2. Revenue recognition: POSTED invoice_status, matching the convention used
--      throughout the shared schema.
--   3. Contra-revenue: APPROVED refund_status netted against gross revenue,
--      joined through fact_refunds.invoice_id -> fact_invoices.invoice_id.
--   4. Currency: filtered to currency_code = 'USD'; no FX conversion table exists
--      in this workspace scope.

CREATE OR REPLACE VIEW shared.metric_arpac_trailing_90_days AS

WITH active_customer_denominator AS (
    -- Reuses dim_customers.is_active as the authoritative active-customer flag
    -- (definition: placed >= 1 order in last 12 months, aligned with exec dashboards)
    SELECT customer_id
    FROM   shared.dim_customers
    WHERE  is_active = TRUE
),

posted_revenue AS (
    -- Gross USD revenue from POSTED invoices in the trailing 90 days,
    -- restricted to active customers only (numerator customer scope)
    SELECT
        fi.customer_id,
        SUM(fi.invoice_amount) AS gross_revenue_usd
    FROM   shared.fact_invoices fi
    INNER JOIN active_customer_denominator acd
           ON acd.customer_id = fi.customer_id
    WHERE  fi.invoice_status = 'POSTED'
      AND  fi.currency_code  = 'USD'
      AND  fi.invoice_date  >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY fi.customer_id
),

approved_refunds AS (
    -- APPROVED USD refunds against trailing-90-day invoices for active customers
    SELECT
        fi.customer_id,
        SUM(fr.refund_amount) AS refund_usd
    FROM   shared.fact_refunds fr
    INNER JOIN shared.fact_invoices fi
           ON fi.invoice_id    = fr.invoice_id
    INNER JOIN active_customer_denominator acd
           ON acd.customer_id  = fi.customer_id
    WHERE  fr.refund_status = 'APPROVED'
      AND  fr.currency_code = 'USD'
      AND  fi.invoice_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY fi.customer_id
),

net_revenue_per_customer AS (
    -- One row per active customer with their net revenue contribution
    SELECT
        acd.customer_id,
        COALESCE(pr.gross_revenue_usd, 0)
            - COALESCE(ar.refund_usd, 0)    AS net_revenue_usd
    FROM   active_customer_denominator acd
    LEFT JOIN posted_revenue   pr ON pr.customer_id = acd.customer_id
    LEFT JOIN approved_refunds ar ON ar.customer_id = acd.customer_id
)

SELECT
    CURRENT_DATE()                                                  AS metric_date,
    COUNT(DISTINCT customer_id)                                     AS active_customer_count,
    SUM(net_revenue_usd)                                            AS net_recognized_revenue_usd,
    SUM(net_revenue_usd)
        / NULLIF(COUNT(DISTINCT customer_id), 0)                   AS arpac_trailing_90_days_usd
FROM net_revenue_per_customer;
