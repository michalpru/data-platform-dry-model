-- finance.reporting.arpac_components.v1  (Snowflake SQL, warehouse runtime)
-- ============================================================================
-- GRAIN: customer_id × reporting_date  (active customers only)
-- Parameter: :reporting_date  DATE  — the "as-of" date for the metric
--
-- PURPOSE:
--   Per-customer components dataset for the trailing-90-day ARPAC metric.
--   Produces one row per active customer per reporting date, carrying:
--     • the customer's identity (denominator contribution)
--     • their net recognized revenue in USD over the 90-day window (numerator contribution)
--   The ARPAC metric (finance.metrics.arpac_trailing_90d.v1) aggregates this
--   dataset: ARPAC = SUM(net_recognized_revenue_usd) / COUNT(customer_id).
--
-- ⚠ CROSS-ENGINE INTEGRATION REQUIRED ⚠
--   sales.datasets.commercial_customer_status_90d.v1 is CERTIFIED (enterprise_canonical)
--   but has NO Snowflake binding — it is bound only to Databricks.
--   The reference below assumes a Snowflake binding has been provisioned under
--   SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D (e.g., via Snowflake external table,
--   Delta Sharing / data share, or a registered mirror view that surfaces the same
--   certified Databricks artifact).
--   DO NOT re-derive the active-customer logic; only a registered bridge binding
--   is permitted. See arpac_metric.yaml → reuses[0].cross_engine_gap for details.
--
-- CERTIFIED ARTIFACTS REUSED:
--   Denominator: sales.datasets.commercial_customer_status_90d.v1
--                Physical binding assumed: SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D
--                Columns confirmed from source: customer_id, reporting_date,
--                                               is_active_commercial_90d
--   Numerator:   finance.logic.recognize_revenue.v1
--                Physical binding resolved: FINANCE.LOGIC.RECOGNIZE_REVENUE (Snowflake UDF)
--                Signature confirmed from source:
--                  FINANCE.LOGIC.RECOGNIZE_REVENUE(P_START_DATE DATE, P_END_DATE DATE)
--                  → TABLE(CUSTOMER_ID NUMBER, BILLABLE_EVENT_ID VARCHAR,
--                           RECOGNITION_DATE DATE, EVENT_TYPE VARCHAR,
--                           SOURCE_CURRENCY VARCHAR, RECOGNIZED_REVENUE_USD NUMBER(18,2))
-- ============================================================================

WITH active_customers AS (
    -- [BRIDGE REQUIRED] Snowflake binding for sales.datasets.commercial_customer_status_90d.v1
    -- must be provisioned before deploying. Column names confirmed from Databricks source.
    SELECT customer_id
    FROM SALES.DATASETS.COMMERCIAL_CUSTOMER_STATUS_90D
    WHERE reporting_date          = :reporting_date
      AND is_active_commercial_90d = TRUE
),

revenue_in_window AS (
    -- finance.logic.recognize_revenue.v1 — certified Finance revenue-recognition rule.
    -- 90-day window: [reporting_date - 89 days, reporting_date] inclusive = 90 days.
    -- Refund/credit-note netting is already applied inside the UDF (signed NET_AMOUNT).
    SELECT
        CUSTOMER_ID,
        SUM(RECOGNIZED_REVENUE_USD) AS net_recognized_revenue_usd
    FROM TABLE(
        FINANCE.LOGIC.RECOGNIZE_REVENUE(
            DATEADD('day', -89, :reporting_date),
            :reporting_date
        )
    )
    GROUP BY CUSTOMER_ID
)

-- Final grain: one row per active customer for this reporting_date.
-- LEFT JOIN ensures active customers with $0 revenue in the window are retained
-- (they still count in the denominator; their revenue contribution is 0).
SELECT
    ac.customer_id,
    :reporting_date                              AS reporting_date,
    COALESCE(rw.net_recognized_revenue_usd, 0)  AS net_recognized_revenue_usd
FROM      active_customers       AS ac
LEFT JOIN revenue_in_window      AS rw
       ON rw.CUSTOMER_ID = ac.customer_id;
