-- arpac-authoring-scratch.sql
-- =========================================================================
-- PATTERN 1 / PATTERN 2 OUTCOME — the "from scratch" reimplementation.
--
-- This is what an analytics engineer + AI assistant produce for ARPAC when the
-- certified artifacts are NOT resolvable at authoring time. It looks correct and
-- runs, but it silently REIMPLEMENTS three governed rules straight from raw tables:
--   * orders -> invoices mapping        (owned by finance.logic.recognize_revenue.v1)
--   * netting (refunds/credit notes)     (owned by finance.logic.recognize_revenue.v1)
--   * currency normalization             (owned by finance.logic.normalize_reporting_currency.v1)
-- and it re-derives the active-customer window with a DIFFERENT threshold (30 days),
-- diverging from the certified enterprise.metrics.active_customer.v1 (90 days).
--
-- Use this file as the duplication-detection input:
--   python -m dry_registry.cli duplicates ../demo/arpac-authoring-scratch.sql \
--       --interface callable_logic --lang sql
-- The registry engine should flag high structural similarity to the certified
-- recognize_revenue UDF AND attach its authority (owner + lifecycle).
-- =========================================================================

WITH invoiced AS (
    -- Re-derived orders->invoices mapping (duplicates recognize_revenue.v1)
    SELECT
        i.invoice_id        AS revenue_event_id,
        o.customer_id       AS customer_id,
        i.invoice_date      AS event_date,
        i.currency          AS source_currency,
        i.amount            AS gross_amount,
        CASE WHEN i.status = 'settled' THEN 'recognized' ELSE 'pending' END AS recognition_status
    FROM finance.raw.orders   AS o
    JOIN finance.raw.invoices AS i
      ON i.order_id = o.order_id
    WHERE i.invoice_date BETWEEN DATE '2025-01-01' AND CURRENT_DATE
),
netting AS (
    -- Re-derived netting rule (duplicates recognize_revenue.v1)
    SELECT r.invoice_id AS invoice_id, SUM(r.amount) AS netting_amount
    FROM finance.raw.refunds AS r
    GROUP BY r.invoice_id
),
revenue AS (
    SELECT
        v.customer_id,
        -- Hardcoded FX join (duplicates normalize_reporting_currency.v1, own convention)
        ROUND(
            (v.gross_amount - COALESCE(n.netting_amount, 0))
            * COALESCE(fx.rate_to_reporting, 1.0), 2
        ) AS recognized_revenue_amount
    FROM invoiced v
    LEFT JOIN netting n ON n.invoice_id = v.revenue_event_id
    LEFT JOIN finance.raw.fx_rates fx
           ON fx.from_currency = v.source_currency
          AND fx.to_currency   = 'USD'
          AND fx.rate_date     = v.event_date
    WHERE v.recognition_status = 'recognized'
),
active AS (
    -- DIVERGENT active-customer window: 30 days, not the certified 90 (Is_Active_Commercial_90d)
    SELECT COUNT(DISTINCT customer_id) AS active_customers
    FROM finance.raw.orders
    WHERE order_date >= DATEADD(day, -30, CURRENT_DATE)
)
SELECT
    SUM(revenue.recognized_revenue_amount) / active.active_customers AS arpac
FROM revenue CROSS JOIN active
GROUP BY active.active_customers;
