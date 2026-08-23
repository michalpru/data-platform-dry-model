-- Snowflake SQL — reusable executive metric view
-- Trailing-90-Day ARPAC (Average Revenue per Active Customer), denominated in USD.
--
-- Adopt by querying finance.metrics.arpac_trailing_90_days directly.
--
-- Reused workspace artifacts (scope: scenario-1c/workspace only):
--   sales.datasets.active_customer_90d     — active-customer definition (trailing-90-day,
--                                             POSTED invoice). Reused as the DENOMINATOR rule.
--   FINANCE.LOGIC.RECOGNIZE_REVENUE()      — net recognized revenue in USD. Reused as the
--                                             NUMERATOR. Handles invoice/refund netting,
--                                             recognition timing, and FX conversion.
--   FINANCE.DATASETS.FACT_BILLABLE_EVENTS  — invoice + refund event source (used indirectly
--                                             through RECOGNIZE_REVENUE).
--   FINANCE.LOGIC.NORMALIZE_CURRENCY()     — FX → USD (used indirectly through
--                                             RECOGNIZE_REVENUE).
--
-- Numerator scope: revenue is restricted to the active-customer denominator; revenue from
-- non-active customers is excluded before aggregation.

CREATE OR REPLACE VIEW finance.metrics.arpac_trailing_90_days AS

WITH active_customers AS (
    -- DENOMINATOR — reuses the active-customer rule from sales.datasets.active_customer_90d:
    -- a customer is active if they have >= 1 POSTED invoice in the trailing 90 days.
    -- Customer universe is shared.dim_customers (as in the source view); the metric evaluates
    -- the single as-of slice at CURRENT_DATE. Spark date_sub(reporting_date, 90) is expressed
    -- as the semantically identical Snowflake DATEADD(DAY, -90, ...).
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
    -- NUMERATOR — delegates entirely to FINANCE.LOGIC.RECOGNIZE_REVENUE for net USD revenue
    -- per customer over the same trailing-90-day window. The function nets POSTED invoices
    -- against APPROVED refunds/credit notes (signed NET_AMOUNT, IS_RECOGNIZABLE) from
    -- FACT_BILLABLE_EVENTS and converts every currency to USD via NORMALIZE_CURRENCY.
    -- Restricted to the active-customer set so only in-denominator revenue is counted.
    SELECT
        rr.CUSTOMER_ID,
        SUM(rr.RECOGNIZED_REVENUE_USD) AS net_recognized_revenue_usd
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
    CURRENT_DATE()                                          AS metric_date,
    COUNT(DISTINCT ac.customer_id)                          AS active_customer_count,
    COALESCE(SUM(rr.net_recognized_revenue_usd), 0)         AS net_recognized_revenue_usd,
    ROUND(
        COALESCE(SUM(rr.net_recognized_revenue_usd), 0)
        / NULLIF(COUNT(DISTINCT ac.customer_id), 0),
        2
    )                                                       AS arpac_trailing_90_days_usd
FROM active_customers AS ac
LEFT JOIN recognized_revenue AS rr
    ON rr.CUSTOMER_ID = ac.customer_id;
