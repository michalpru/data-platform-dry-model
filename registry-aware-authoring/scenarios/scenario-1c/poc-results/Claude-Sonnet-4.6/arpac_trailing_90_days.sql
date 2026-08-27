-- Snowflake SQL — reusable executive metric view
-- Trailing-90-Day ARPAC (Average Revenue per Active Customer)
--
-- Sources (workspace scope: scenario-1c/workspace only):
--   sales.datasets.active_customer_90d      — active-customer definition (exec dashboards)
--   FINANCE.LOGIC.RECOGNIZE_REVENUE()       — net recognized revenue, USD, with FX conversion
--   FINANCE.DATASETS.FACT_BILLABLE_EVENTS   — (called indirectly via RECOGNIZE_REVENUE)
--   FINANCE.LOGIC.NORMALIZE_CURRENCY()      — (called indirectly via RECOGNIZE_REVENUE)
--
-- Reuse notes:
--   1. Active-customer definition: logic ported from sales.datasets.active_customer_90d
--      (POSTED invoice in the trailing 90 days) — the definition already used by the
--      sales/executive trailing-90-day reporting layer.  Adapted from Spark SQL (date_sub)
--      to Snowflake (DATEADD) with identical semantics.
--   2. Net recognized revenue: delegates entirely to FINANCE.LOGIC.RECOGNIZE_REVENUE,
--      which nets POSTED invoices and APPROVED refunds/credit notes from
--      FINANCE.DATASETS.FACT_BILLABLE_EVENTS and converts every currency to USD via
--      FINANCE.LOGIC.NORMALIZE_CURRENCY.  No revenue or FX logic is re-implemented here.
--   3. Numerator customer scope: revenue is filtered to active customers only by joining
--      the RECOGNIZE_REVENUE output against the active_customers CTE before aggregation.

CREATE OR REPLACE VIEW finance.metrics.arpac_trailing_90_days AS

WITH active_customers AS (
    -- Reuses the active-customer rule from sales.datasets.active_customer_90d:
    -- a customer is active if they have at least one POSTED invoice in the trailing
    -- 90 days.  Evaluated at CURRENT_DATE (the single-date slice of the date-series view).
    SELECT DISTINCT
        c.customer_id
    FROM shared.dim_customers AS c
    JOIN shared.fact_invoices AS i
        ON  i.customer_id    = c.customer_id
        AND i.invoice_status = 'POSTED'
        AND i.invoice_date  >= DATEADD(DAY, -90, CURRENT_DATE())
        AND i.invoice_date  <= CURRENT_DATE()
),

recognized_revenue AS (
    -- Delegates to FINANCE.LOGIC.RECOGNIZE_REVENUE for net USD revenue per customer.
    -- The function handles FX conversion (NORMALIZE_CURRENCY) and nets invoices against
    -- refunds/credit notes via IS_RECOGNIZABLE and NET_AMOUNT signs in FACT_BILLABLE_EVENTS.
    -- Revenue is restricted to the active-customer set before aggregation.
    SELECT
        rr.CUSTOMER_ID,
        SUM(rr.RECOGNIZED_REVENUE_USD) AS net_revenue_usd
    FROM TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(
            DATEADD(DAY, -90, CURRENT_DATE()),
            CURRENT_DATE()
        )
    ) AS rr
    WHERE rr.CUSTOMER_ID IN (SELECT customer_id FROM active_customers)
    GROUP BY rr.CUSTOMER_ID
)

SELECT
    CURRENT_DATE()                                                AS metric_date,
    COUNT(DISTINCT ac.customer_id)                               AS active_customer_count,
    COALESCE(SUM(rr.net_revenue_usd), 0)                         AS net_recognized_revenue_usd,
    ROUND(
        COALESCE(SUM(rr.net_revenue_usd), 0)
        / NULLIF(COUNT(DISTINCT ac.customer_id), 0),
        2
    )                                                            AS arpac_trailing_90_days_usd
FROM active_customers AS ac
LEFT JOIN recognized_revenue AS rr
    ON rr.CUSTOMER_ID = ac.customer_id;
