-- finance.marts.revenue_events.v1.sql
-- Domain: finance | Lifecycle: certified
--
-- Produces: finance.reporting.revenue_events.v1
-- Contract:  domains/finance/contracts/datasets/finance.reporting.revenue_events.v1.contract.yaml
--
-- Reuses:
--   - dry_shared_macros.with_boolean_flag  (platform package: dry_shared_macros v0.1.0)
--     DRY in Code: the *how* of boolean flag computation is platform-shared;
--     the *what* (recognition condition) is domain-specific and lives here.
--
--   - enterprise.reporting.customer.v1  (enterprise certified customer master)
--     DRY in Physical Data Assets: joins to the single canonical customer entity
--     rather than rebuilding customer attributes from source systems.
--
-- This is the canonical definition of a recognized revenue event for the Finance domain.
-- Downstream consumers must reference the dataset contract, not query this model directly.

{{ config(materialized='table') }}

SELECT
    r.revenue_event_id,
    r.customer_id,
    CAST(r.event_ts AS DATE)                                                  AS event_date,
    r.amount,
    -- Platform macro encodes *how* to compute the flag; the business condition is local
    {{ with_boolean_flag('r.recognition_status = \'recognized\'') }}         AS is_recognized
FROM finance.raw.revenue_events         AS r
INNER JOIN {{ source('enterprise', 'customer') }} AS c  -- enterprise.reporting.customer.v1
    ON r.customer_id = c.customer_id
WHERE
    r.recognition_status = 'recognized'
