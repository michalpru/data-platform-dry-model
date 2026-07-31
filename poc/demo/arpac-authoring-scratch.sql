-- arpac-authoring-scratch.sql
-- =========================================================================
-- PATTERN 1 / PATTERN 2 OUTCOME — the "from scratch" reimplementation.
--
-- This is what an analytics engineer + AI assistant produce for ARPAC when the
-- certified artifacts are NOT resolvable at authoring time. It looks correct and
-- runs, but it silently REIMPLEMENTS governed rules straight from the visible base
-- tables (SHARED.DATASETS.FACT_INVOICES / FACT_REFUNDS / DIM_CUSTOMERS,
-- FINANCE.DATASETS.DIM_EXCHANGE_RATES):
--   * billable-event assembly (invoices UNION refunds, signed amounts)
--        (owned by finance.datasets.fact_billable_events.v1)
--   * refund netting + recognition            (owned by finance.logic.recognize_revenue.v1)
--   * currency normalization                  (owned by finance.logic.normalize_currency.v1)
-- and it uses the WRONG active-customer definition: DIM_CUSTOMERS.IS_ACTIVE is a 12-month
-- operational order flag, not the certified 90-day commercial-activity status
-- (sales.datasets.commercial_customer_status_90d.v1).
--
-- Use this file as the duplication-detection input:
--   python -m dry_registry.cli duplicates ../demo/arpac-authoring-scratch.sql \
--       --interface queryable_dataset --lang sql
-- The registry engine should flag high structural similarity to the certified
-- fact_billable_events / recognize_revenue artifacts AND attach their authority
-- (owner + lifecycle).
-- =========================================================================

WITH invoice_events AS (
    -- Re-derived invoice leg (duplicates fact_billable_events.v1)
    SELECT
        i.customer_id,
        i.invoice_date      AS event_date,
        i.currency_code,
        i.invoice_amount    AS amount
    FROM shared.datasets.fact_invoices AS i
    WHERE i.invoice_status = 'POSTED'
),
refund_events AS (
    -- Re-derived refund leg with signed amount (duplicates fact_billable_events.v1 netting)
    SELECT
        r.customer_id,
        r.refund_date       AS event_date,
        r.currency_code,
        -r.refund_amount    AS amount
    FROM shared.datasets.fact_refunds AS r
    WHERE r.refund_status = 'APPROVED'
),
billable AS (
    SELECT * FROM invoice_events
    UNION ALL
    SELECT * FROM refund_events
),
revenue AS (
    -- Re-derived recognition + currency normalization (duplicates recognize_revenue.v1)
    SELECT
        b.customer_id,
        SUM(ROUND(b.amount * fx.exchange_rate, 2)) AS net_revenue_usd
    FROM billable AS b
    JOIN finance.datasets.dim_exchange_rates AS fx
      ON fx.from_currency = b.currency_code
     AND fx.to_currency   = 'USD'
     AND fx.rate_date     = b.event_date
    WHERE b.event_date >= DATEADD(day, -90, CURRENT_DATE())
    GROUP BY b.customer_id
),
active AS (
    -- WRONG active-customer rule: 12-month operational flag, not the certified 90-day status
    SELECT customer_id
    FROM shared.datasets.dim_customers
    WHERE is_active = TRUE
)
SELECT
    SUM(revenue.net_revenue_usd)
    / NULLIF(COUNT(DISTINCT active.customer_id), 0) AS arpac_90d_usd
FROM revenue
JOIN active ON active.customer_id = revenue.customer_id;
