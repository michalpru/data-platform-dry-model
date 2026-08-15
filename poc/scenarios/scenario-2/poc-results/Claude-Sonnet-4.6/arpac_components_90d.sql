-- =============================================================================
-- exec.datasets.arpac_components_90d
-- Grain: CUSTOMER_ID x REPORTING_DATE
--
-- PURPOSE:
--   Intermediate components dataset for the ARPAC (trailing-90-day) metric.
--   Produces one row per active customer per reporting date with net recognized
--   revenue (USD) attributed to that customer over the trailing 90-day window.
--   Only customers classified as active contribute rows; non-active customers
--   are excluded, which ensures the numerator and denominator share the same
--   customer population.
--
-- REUSED ARTIFACTS:
--   [DENOMINATOR] sales.datasets.commercial_customer_status_90d.v1
--     Authority : REGISTERED_CANONICAL  |  Lifecycle: certified
--     Owner     : sales-analytics       |  Reuse intent: enterprise_canonical
--     Binding   : sales.datasets.commercial_customer_status_90d
--                 [Databricks, prod]
--     *** CROSS-ENGINE GAP ***
--     No Snowflake (warehouse) binding is registered for this artifact.
--     This SQL references the Databricks binding by name. It is runnable
--     end-to-end in Snowflake ONLY after a Snowflake binding (External Table,
--     data sharing grant, or registered Snowflake view) is provisioned and
--     registered for sales.datasets.commercial_customer_status_90d.v1.
--     Integration requirement: file a binding-registration request with
--     sales-analytics and platform-dwh to close this gap.
--
--   [NUMERATOR]  finance.logic.recognize_revenue.v1
--     Authority : REGISTERED_CANONICAL  |  Lifecycle: certified
--     Owner     : finance-analytics     |  Reuse intent: enterprise_canonical
--     Binding   : FINANCE.LOGIC.RECOGNIZE_REVENUE
--                 [Snowflake warehouse, prod, object_type: udf]
--
-- UNCONFIRMED IDENTIFIERS:
--   Column names from sales.datasets.commercial_customer_status_90d.v1 could
--   not be verified (source file unreachable). The following identifiers are
--   marked [UNCONFIRMED] and MUST be confirmed against the source at
--   sales/datasets/commercial_customer_status_90d.sql before promotion:
--     - CUSTOMER_ID
--     - REPORTING_DATE
--     - IS_ACTIVE_COMMERCIAL_90D
--   UDF call signature for FINANCE.LOGIC.RECOGNIZE_REVENUE is [UNCONFIRMED].
--   Confirm parameter names, order, and return type from
--   finance/logic/recognize_revenue.sql before promotion.
--
-- PRECONDITION (engine reachability):
--   sales.datasets.commercial_customer_status_90d must be accessible from the
--   Snowflake warehouse runtime. Reference the Databricks binding below is
--   intentional — it names the certified artifact's only existing binding.
--   Replace the reference with the registered Snowflake binding object name
--   once that binding is provisioned.
-- =============================================================================

CREATE OR REPLACE VIEW exec.datasets.arpac_components_90d AS

WITH active_customers AS (
    -- Certified enterprise active-customer definition
    -- Source: sales.datasets.commercial_customer_status_90d.v1 (enterprise_canonical)
    -- Binding: sales.datasets.commercial_customer_status_90d [Databricks prod]
    -- PRECONDITION: assumes reachable from Snowflake warehouse once a binding is provisioned
    SELECT
        CUSTOMER_ID,                -- [UNCONFIRMED — verify from sales/datasets/commercial_customer_status_90d.sql]
        REPORTING_DATE              -- [UNCONFIRMED — verify from sales/datasets/commercial_customer_status_90d.sql]
    FROM sales.datasets.commercial_customer_status_90d  -- Databricks binding ref
    WHERE IS_ACTIVE_COMMERCIAL_90D = TRUE               -- [UNCONFIRMED — verify column name]
),

customer_revenue AS (
    -- Net recognized revenue (USD) per active customer for the trailing 90-day window.
    -- Source: finance.logic.recognize_revenue.v1 (enterprise_canonical)
    -- Binding: FINANCE.LOGIC.RECOGNIZE_REVENUE [Snowflake warehouse prod, udf]
    -- UDF call signature (parameters and return column name) is [UNCONFIRMED].
    -- Confirm arity and parameter names from finance/logic/recognize_revenue.sql.
    -- The call below assumes the UDF accepts (customer_id, window_start, window_end)
    -- and returns a scalar net_revenue_usd value; adjust if the actual signature differs.
    SELECT
        ac.CUSTOMER_ID,
        ac.REPORTING_DATE,
        FINANCE.LOGIC.RECOGNIZE_REVENUE(    -- certified UDF; signature [UNCONFIRMED]
            ac.CUSTOMER_ID,                 -- [UNCONFIRMED: parameter 1 — customer identifier]
            DATEADD('day', -89, ac.REPORTING_DATE),  -- trailing-90-day window start
            ac.REPORTING_DATE               -- [UNCONFIRMED: parameter 3 — window end inclusive]
        ) AS NET_REVENUE_USD               -- [UNCONFIRMED: return value / column name]
    FROM active_customers AS ac
)

SELECT
    CUSTOMER_ID,
    REPORTING_DATE,
    COALESCE(NET_REVENUE_USD, 0) AS NET_REVENUE_USD  -- zero-fill for active customers with no events
FROM customer_revenue;
