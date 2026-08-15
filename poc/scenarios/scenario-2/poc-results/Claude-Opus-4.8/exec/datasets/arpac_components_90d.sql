-- exec.datasets.arpac_components_90d  (Snowflake SQL table function)
-- =========================================================================
-- Registry FQN (proposed): exec.datasets.arpac_components_90d.v1  (queryable dataset)
-- Owner: executive-analytics | Lifecycle: proposed
--
-- Building-block dataset for the trailing-90-day ARPAC metric. Emits ONE row per
-- (reporting_date x active customer) carrying that customer's trailing-90-day NET recognized
-- revenue in USD. Non-active customers are excluded by construction (the active-customer set
-- drives the join), so downstream aggregation counts revenue ONLY from customers in the
-- denominator.
--
-- This is a governed COMPOSITION over certified enterprise-canonical inputs; it re-derives
-- nothing. Every input is a resolved registry binding:
--   * Numerator input   : finance.logic.recognize_revenue.v1
--                         binding warehouse:snowflake:FINANCE.LOGIC.RECOGNIZE_REVENUE (table UDF)
--   * Denominator input : sales.datasets.commercial_customer_status_90d.v1
--                         binding databricks:sales.datasets.commercial_customer_status_90d (view)
--
-- >>> CROSS-ENGINE PRECONDITION (integration requirement, NOT satisfied by this file) <<<
-- The certified active-customer definition (sales.datasets.commercial_customer_status_90d.v1)
-- resolves ONLY to a Databricks binding. There is no Snowflake binding for it. This function is
-- authored on Snowflake (where the certified revenue rule lives) and references that artifact by
-- its resolved Databricks-bound name under the explicit assumption that it is REACHABLE FROM
-- SNOWFLAKE once a target-engine binding is provisioned -- e.g. via the portable-SQL framework,
-- or a shared/federated view registered in the registry as an ADDITIONAL Snowflake binding for the
-- same artifact. No bridge object is invented here; provisioning that binding is a prerequisite to
-- run this code. Until then the reference below is a placeholder for the resolved artifact.
-- =========================================================================
CREATE OR REPLACE FUNCTION EXEC.DATASETS.ARPAC_COMPONENTS_90D(
    P_REPORTING_DATE DATE
)
RETURNS TABLE (
    REPORTING_DATE              DATE,
    CUSTOMER_ID                 NUMBER(38, 0),
    RECOGNIZED_REVENUE_USD_90D  NUMBER(18, 2)
)
LANGUAGE SQL
AS
$$
    WITH active_customers AS (
        -- Denominator population: distinct customers flagged active at the reporting date by the
        -- enterprise active-customer definition used by executive dashboards.
        -- Reachability precondition applies to this reference (see header).
        SELECT DISTINCT
            s.customer_id,
            s.reporting_date
        FROM sales.datasets.commercial_customer_status_90d AS s
        WHERE s.reporting_date = P_REPORTING_DATE
          AND s.is_active_commercial_90d = TRUE
    ),
    revenue_trailing_90d AS (
        -- Numerator input: net recognized revenue (USD) per customer over the trailing 90 days,
        -- window aligned to the active-customer definition: [reporting_date - 90, reporting_date].
        -- RECOGNIZED_REVENUE_USD is already net (refunds/credit notes carried in signed NET_AMOUNT).
        SELECT
            r.CUSTOMER_ID,
            SUM(r.RECOGNIZED_REVENUE_USD) AS RECOGNIZED_REVENUE_USD_90D
        FROM TABLE(FINANCE.LOGIC.RECOGNIZE_REVENUE(
                 DATEADD('day', -90, P_REPORTING_DATE),
                 P_REPORTING_DATE
             )) AS r
        GROUP BY r.CUSTOMER_ID
    )
    SELECT
        ac.reporting_date                            AS REPORTING_DATE,
        ac.customer_id                               AS CUSTOMER_ID,
        COALESCE(rev.RECOGNIZED_REVENUE_USD_90D, 0)  AS RECOGNIZED_REVENUE_USD_90D
    FROM active_customers AS ac
    LEFT JOIN revenue_trailing_90d AS rev
        ON rev.CUSTOMER_ID = ac.customer_id
$$;
