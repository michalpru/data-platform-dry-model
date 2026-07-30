-- finance.marts.revenue_events.v1.sql
-- Domain: finance | Lifecycle: certified
--
-- Produces: finance.reporting.revenue_events.v1  (queryable dataset)
-- Contract:  domains/finance/contracts/datasets/finance.reporting.revenue_events.v1.contract.yaml
--
-- This transformation model is DRY in Logic by COMPOSITION: it re-uses three published
-- callable-logic artifacts and one canonical entity rather than re-deriving revenue.
--
-- Reuses:
--   - finance.logic.recognize_revenue.v1  (table-valued SQL UDF)
--       Orders->invoices mapping + netting rule (gross - refunds/credit notes).
--       Called as a table function; the model does NOT re-join raw orders/invoices/refunds.
--
--   - finance.logic.normalize_reporting_currency.v1  (finance SQL macro)
--       Currency rule: converts the netted amount to the enterprise reporting currency
--       as-of the event date. The FX table and rounding live in the macro, not here.
--
--   - dry_shared_macros.with_boolean_flag  (platform package: dry_shared_macros v0.1.0)
--       DRY in Code: the *how* of boolean flag computation is platform-shared;
--       the *what* (recognition condition) is domain-specific and lives here.
--
--   - enterprise.reporting.customer.v1  (enterprise certified customer master)
--       DRY in Physical Data Assets: joins to the single canonical customer entity
--       rather than rebuilding customer attributes from source systems.
--
-- This is the canonical definition of a recognized revenue event for the Finance domain.
-- Downstream consumers must reference the dataset contract, not query this model directly.

{{ config(materialized='table') }}

SELECT
    e.revenue_event_id,
    e.customer_id,
    e.event_date,
    -- Currency rule is centralized in the finance macro, not re-derived here:
    {{ normalize_reporting_currency('e.net_amount', 'e.source_currency', 'e.event_date') }}
        AS recognized_revenue_amount,
    -- Platform macro encodes *how* to compute the flag; the business condition is local:
    {{ with_boolean_flag("e.recognition_status = 'recognized'") }}       AS is_recognized
FROM TABLE({{ source('finance', 'fn_recognize_revenue') }}(
        DATE '2025-01-01', CURRENT_DATE))            AS e   -- finance.logic.recognize_revenue.v1
INNER JOIN {{ source('enterprise', 'customer') }}   AS c   -- enterprise.reporting.customer.v1
    ON e.customer_id = c.customer_id
WHERE
    e.recognition_status = 'recognized'
