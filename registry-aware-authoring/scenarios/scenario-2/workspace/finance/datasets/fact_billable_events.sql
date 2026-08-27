-- finance.datasets.fact_billable_events  (Snowflake SQL)
-- =========================================================================
-- Registry FQN: finance.datasets.fact_billable_events.v1  (queryable dataset)
-- Owner: finance-analytics | Lifecycle: certified
--
-- Finance-owned canonical stream of billable financial events: one standardized event stream
-- regardless of operational source. Maps invoice events and refund/credit-note events, nets
-- refunds via a signed NET_AMOUNT, standardizes recognition dates, statuses and source systems.
--
-- This is the UPSTREAM source that finance.logic.recognize_revenue.v1 reads from; consumers must
-- NOT re-derive billable events by re-joining raw invoices and refunds.
-- =========================================================================
CREATE OR REPLACE TABLE FINANCE.DATASETS.FACT_BILLABLE_EVENTS AS

WITH invoice_events AS (
    SELECT
        'INVOICE:' || TO_VARCHAR(i.INVOICE_ID) AS BILLABLE_EVENT_ID,
        i.CUSTOMER_ID,
        i.CONTRACT_ID,
        i.PRODUCT_ID,
        i.INVOICE_DATE AS EVENT_DATE,
        COALESCE(i.POSTED_DATE, i.INVOICE_DATE) AS RECOGNITION_DATE,
        i.CURRENCY_CODE,
        i.INVOICE_AMOUNT AS NET_AMOUNT,
        'INVOICE' AS EVENT_TYPE,
        i.INVOICE_STATUS AS EVENT_STATUS,
        IFF(i.INVOICE_STATUS = 'POSTED', TRUE, FALSE) AS IS_RECOGNIZABLE,
        i.SOURCE_SYSTEM,
        TO_VARCHAR(i.INVOICE_ID) AS SOURCE_RECORD_ID
    FROM SHARED.DATASETS.FACT_INVOICES AS i
),

refund_events AS (
    SELECT
        'REFUND:' || TO_VARCHAR(r.REFUND_ID) AS BILLABLE_EVENT_ID,
        r.CUSTOMER_ID,
        r.CONTRACT_ID,
        r.PRODUCT_ID,
        r.REFUND_DATE AS EVENT_DATE,
        COALESCE(r.APPROVED_DATE, r.REFUND_DATE) AS RECOGNITION_DATE,
        r.CURRENCY_CODE,
        -ABS(r.REFUND_AMOUNT) AS NET_AMOUNT,
        IFF(r.REFUND_TYPE = 'CREDIT_NOTE', 'CREDIT_NOTE', 'REFUND') AS EVENT_TYPE,
        r.REFUND_STATUS AS EVENT_STATUS,
        IFF(r.REFUND_STATUS = 'APPROVED', TRUE, FALSE) AS IS_RECOGNIZABLE,
        r.SOURCE_SYSTEM,
        TO_VARCHAR(r.REFUND_ID) AS SOURCE_RECORD_ID
    FROM SHARED.DATASETS.FACT_REFUNDS AS r
)

SELECT * FROM invoice_events
UNION ALL
SELECT * FROM refund_events;

COMMENT ON TABLE FINANCE.DATASETS.FACT_BILLABLE_EVENTS IS
'Finance-owned canonical stream of invoice, refund, and credit-note events. Standardizes event identifiers, recognition dates, signed amounts, statuses, and source systems.';
