-- PROBE (negative control): a fresh reimplementation of legacy invoice-based revenue.
-- Hand-written to look like "new original code": renamed CTE/aliases, reordered predicates,
-- reformatted. Semantically it is the RETIRED finance.datasets.invoice_revenue rule — posted
-- invoices only, currency-normalized, refunds and credit notes excluded, invoice-date timing.
-- Expectation: the registry surfaces the retired artifact (lifecycle: retired) so the engineer
-- is warned NOT to reuse it, even though workspace search would happily treat it as reusable.
CREATE OR REPLACE VIEW REPORTING.CUSTOMER_REVENUE_USD AS
SELECT
    inv.CUSTOMER_ID                       AS customer_id,
    inv.INVOICE_ID                        AS invoice_id,
    inv.INVOICE_DATE                      AS revenue_date,
    inv.CURRENCY_CODE                     AS source_currency,
    inv.INVOICE_AMOUNT                    AS source_amount,
    conv.CONVERTED_AMOUNT                 AS revenue_usd
FROM SHARED.DATASETS.FACT_INVOICES AS inv,
LATERAL TABLE(
    FINANCE.LOGIC.NORMALIZE_CURRENCY(
        inv.INVOICE_AMOUNT,
        inv.CURRENCY_CODE,
        'USD',
        inv.INVOICE_DATE
    )
) AS conv
WHERE inv.INVOICE_STATUS = 'POSTED'
  AND inv.INVOICE_AMOUNT IS NOT NULL;
