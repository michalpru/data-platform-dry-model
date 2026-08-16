-- finance.datasets.invoice_revenue  (Snowflake SQL — INTENTIONALLY RETIRED legacy view)
-- =========================================================================
-- Registry FQN: finance.datasets.invoice_revenue.v1  (queryable dataset, lifecycle: retired)
-- Owner: finance-analytics
--
-- Legacy invoice-based revenue view. Computes customer revenue only from POSTED invoices with
-- currency normalization; it EXCLUDES refunds and credit notes and applies no recognition-timing
-- rules. Superseded by the certified recognized-revenue path
-- (finance.datasets.fact_billable_events -> finance.logic.recognize_revenue). Retained ONLY to
-- reproduce the Scenario 1B failure mode (legacy code that looks reusable but must not be reused).
-- =========================================================================
CREATE OR REPLACE VIEW FINANCE.DATASETS.INVOICE_REVENUE AS

SELECT
    i.INVOICE_ID,
    i.CUSTOMER_ID,
    i.INVOICE_DATE AS REVENUE_DATE,
    i.CURRENCY_CODE AS SOURCE_CURRENCY,
    i.INVOICE_AMOUNT AS SOURCE_AMOUNT,
    fx.CONVERTED_AMOUNT AS INVOICE_REVENUE_USD
FROM SHARED.DATASETS.FACT_INVOICES AS i,
LATERAL TABLE(
    FINANCE.LOGIC.NORMALIZE_CURRENCY(
        i.INVOICE_AMOUNT,
        i.CURRENCY_CODE,
        'USD',
        i.INVOICE_DATE
    )
) AS fx
WHERE i.INVOICE_AMOUNT IS NOT NULL
  AND i.INVOICE_STATUS = 'POSTED';

COMMENT ON VIEW FINANCE.DATASETS.INVOICE_REVENUE IS
'Legacy invoice-based revenue view. Uses invoice date, excludes refunds and credit notes, and must not be used for new executive reporting.';
