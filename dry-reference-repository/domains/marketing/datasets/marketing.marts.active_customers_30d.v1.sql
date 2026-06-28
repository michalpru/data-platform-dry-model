-- marketing.marts.active_customers_30d.v1.sql
-- Domain: marketing | Lifecycle: local (domain-specific, 30-day campaign targeting window)
--
-- IMPORTANT: This dataset uses a 30-day activity window, intended for campaign audience segmentation.
-- For cross-domain comparison or executive reporting, use enterprise.metrics.active_customer.v1 (90-day).
--
-- Reuses:
--   - enterprise.reporting.customer.v1   (enterprise certified customer master)
--   - dry_shared_macros.with_boolean_flag (platform package: dry_shared_macros)

{{ config(materialized='table') }}

SELECT
    c.customer_id,
    c.customer_segment,
    c.region,
    c.acquired_date,
    c.last_activity_date,
    -- Reusing platform macro for boolean flag computation
    {{ with_boolean_flag('c.last_activity_date >= DATEADD(day, -30, CURRENT_DATE)', 'is_active_30d') }}
FROM {{ source('enterprise', 'customer') }} AS c  -- references enterprise.reporting.customer.v1
WHERE c.last_activity_date IS NOT NULL
