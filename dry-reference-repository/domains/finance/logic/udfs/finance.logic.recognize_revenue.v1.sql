-- finance.logic.recognize_revenue.v1  (callable logic — table-valued SQL UDF)
-- Domain: finance | Lifecycle: certified | Owner: finance-analytics
--
-- Canonical revenue-recognition rule for the Finance domain. This is one of the
-- Implementation Bindings of the logical identity finance.logic.recognize_revenue.v1;
-- the dbt macro binding that calls this UDF lives in ../macros/finance.logic.recognize_revenue.v1.sql.
--
-- Encapsulates two business rules that must not diverge across teams:
--   1. Orders -> Invoices mapping: a revenue event exists only where an order has
--      been invoiced (an order alone is not revenue).
--   2. Netting rule: net amount = invoiced gross - (refunds + credit notes),
--      computed in the invoice's source currency. Currency normalization to the
--      enterprise reporting currency is applied downstream by the
--      finance.logic.normalize_reporting_currency.v1 macro, so this UDF stays
--      currency-agnostic and reusable by any consumer.
--
-- Consumed by: finance.reporting.revenue_events.v1 (transformation model).
-- Consumers must call this UDF instead of re-deriving revenue from raw tables.

CREATE OR REPLACE FUNCTION analytics.finance.fn_recognize_revenue(
    start_date DATE,
    end_date   DATE
)
RETURNS TABLE (
    revenue_event_id   STRING,
    customer_id        STRING,
    event_date         DATE,
    source_currency    STRING,
    gross_amount       NUMBER(18, 2),
    netting_amount     NUMBER(18, 2),
    net_amount         NUMBER(18, 2),
    recognition_status STRING
)
AS
$$
    WITH invoiced AS (
        -- Orders -> invoices mapping
        SELECT
            i.invoice_id                                          AS revenue_event_id,
            o.customer_id                                         AS customer_id,
            i.invoice_date                                        AS event_date,
            i.currency                                            AS source_currency,
            i.amount                                              AS gross_amount,
            CASE WHEN i.status = 'settled'
                 THEN 'recognized' ELSE 'pending' END             AS recognition_status
        FROM finance.raw.orders   AS o
        JOIN finance.raw.invoices AS i
          ON i.order_id = o.order_id
        WHERE i.invoice_date BETWEEN start_date AND end_date
    ),
    netting AS (
        -- Netting rule: refunds and credit notes reduce recognized revenue
        SELECT
            r.invoice_id                                          AS invoice_id,
            SUM(r.amount)                                         AS netting_amount
        FROM finance.raw.refunds AS r
        GROUP BY r.invoice_id
    )
    SELECT
        v.revenue_event_id,
        v.customer_id,
        v.event_date,
        v.source_currency,
        v.gross_amount,
        COALESCE(n.netting_amount, 0)                             AS netting_amount,
        v.gross_amount - COALESCE(n.netting_amount, 0)           AS net_amount,
        v.recognition_status
    FROM invoiced AS v
    LEFT JOIN netting AS n
      ON n.invoice_id = v.revenue_event_id
$$;
