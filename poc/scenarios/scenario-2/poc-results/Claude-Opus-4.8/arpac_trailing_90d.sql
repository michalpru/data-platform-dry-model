-- =====================================================================================
-- Metric: Trailing-90-day ARPAC (Average Revenue per Active Customer), in USD
-- Audience: Executive reporting
-- Definition: ARPAC = net recognized revenue (USD) / number of active customers
-- Runtime / dialect authored for: warehouse / snowflake
-- =====================================================================================
--
-- REUSE (governed artifacts resolved via the DRY registry — nothing re-derived):
--
--   1) Net recognized revenue in USD
--      Artifact : finance.logic.recognize_revenue.v1
--      Authority: REGISTERED_CANONICAL | lifecycle=certified | owner=finance-analytics
--                 reuse_intent=domain_canonical
--      Binding  : warehouse/snowflake UDF  FINANCE.LOGIC.RECOGNIZE_REVENUE
--      Why      : This certified rule already reads the canonical billable-event stream
--                 (finance.datasets.fact_billable_events.v1), keeps only recognizable
--                 events in the requested window, nets refunds/credit notes, and
--                 normalizes each signed amount to USD via finance.logic.normalize_currency.v1.
--                 We therefore do NOT recompute revenue from raw invoices/refunds and do
--                 NOT use the retired finance.datasets.invoice_revenue.v1 (which skips
--                 refunds and recognition timing).
--
--   2) Active-customer definition (aligned with other executive dashboards)
--      Artifact : sales.datasets.commercial_customer_status_90d.v1
--      Authority: REGISTERED_CANONICAL | lifecycle=certified | owner=sales-analytics
--                 reuse_intent=enterprise_canonical
--      Binding  : databricks view  sales.datasets.commercial_customer_status_90d
--      Why      : The registry names this the enterprise active-customer definition used
--                 by executive dashboards (authoritative is_active_commercial_90d at
--                 customer x reporting-date grain). We deliberately do NOT use the
--                 shared.datasets.dim_customers.v1 IS_ACTIVE flag, which the registry marks
--                 as a 12-month operational activity flag and NOT the executive definition.
--
-- NEW work (the only thing authored here): the small composition that divides the reused
-- revenue component by the reused active-customer component over a trailing-90-day window.
-- No single ARPAC artifact exists in the registry.
--
-- -------------------------------------------------------------------------------------
-- GOVERNANCE / BINDING NOTES — please read before running:
--
--   * CROSS-RUNTIME GAP: resolve_binding(sales.datasets.commercial_customer_status_90d.v1,
--     runtime=warehouse, dialect=snowflake) returned NO matching binding — the only
--     binding is a Databricks view. The certified revenue rule, by contrast, is a
--     Snowflake warehouse UDF. There is therefore no single-engine physical path today.
--     Reuse (not re-derivation) is the correct call, so this query references each
--     artifact at its certified binding and assumes the active-customer view is made
--     reachable from the warehouse (e.g. via replication/federation into
--     SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D). Do NOT re-implement the
--     active-customer logic in Snowflake — that would duplicate a certified artifact.
--     Ask platform-dwh / sales-analytics to provision a warehouse binding.
--
--   * INTERFACE DETAILS NOT EXPOSED BY THE REGISTRY: the registry returned governance and
--     bindings but not column names or the UDF signature. The identifiers used below
--     (the UDF's window parameters and output column, plus CUSTOMER_ID / REPORTING_DATE /
--     IS_ACTIVE_COMMERCIAL_90D) are placeholders and MUST be confirmed against each
--     artifact's binding contract before this runs.
-- -------------------------------------------------------------------------------------

WITH params AS (
    -- As-of reporting date for the trailing-90-day window (bind at query time).
    SELECT DATE '2026-08-07' AS reporting_date
),

window_bounds AS (
    SELECT
        reporting_date,
        DATEADD(DAY, -89, reporting_date) AS window_start_date,  -- 90-day inclusive window
        reporting_date                    AS window_end_date
    FROM params
),

-- Component 1 — REUSE finance.logic.recognize_revenue.v1 (certified UDF).
-- Called as a table function over the trailing-90-day window; output is already net and
-- already in USD, so we only aggregate it.
recognized_revenue AS (
    SELECT
        SUM(rr.net_recognized_revenue_usd) AS net_recognized_revenue_usd
    FROM window_bounds AS wb,
         TABLE(FINANCE.LOGIC.RECOGNIZE_REVENUE(wb.window_start_date, wb.window_end_date)) AS rr
),

-- Component 2 — REUSE sales.datasets.commercial_customer_status_90d.v1 (certified view).
-- Active customers = distinct customers flagged active at the reporting date. The 90-day
-- lookback is intrinsic to this artifact's is_active_commercial_90d definition.
active_customers AS (
    SELECT
        COUNT(DISTINCT ccs.customer_id) AS active_customer_count
    FROM SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D AS ccs
    JOIN window_bounds AS wb
      ON ccs.reporting_date = wb.reporting_date
    WHERE ccs.is_active_commercial_90d = TRUE
)

-- Composition (the only new logic): ARPAC = net recognized revenue (USD) / active customers.
SELECT
    wb.reporting_date,
    wb.window_start_date,
    wb.window_end_date,
    rr.net_recognized_revenue_usd,
    ac.active_customer_count,
    CASE
        WHEN ac.active_customer_count > 0
            THEN rr.net_recognized_revenue_usd / ac.active_customer_count
        ELSE NULL  -- guard against divide-by-zero when no active customers in window
    END AS arpac_usd
FROM window_bounds AS wb
CROSS JOIN recognized_revenue AS rr
CROSS JOIN active_customers  AS ac;
