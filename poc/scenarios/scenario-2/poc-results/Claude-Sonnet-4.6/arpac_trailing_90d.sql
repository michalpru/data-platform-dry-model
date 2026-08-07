/*
 * ============================================================
 * ARPAC – Trailing-90-Day Average Revenue per Active Customer
 * Executive Reporting Metric
 * ============================================================
 *
 * Formula
 * -------
 *   ARPAC = SUM(net recognised revenue USD over 90 days)
 *           ─────────────────────────────────────────────
 *           COUNT(DISTINCT active commercial customers)
 *
 * Artifact composition – all components resolved from the DRY registry:
 *
 *   Component                  Artifact (FQN)                                    Binding ref                                   Lifecycle / Owner
 *   ─────────────────────────  ────────────────────────────────────────────────  ────────────────────────────────────────────  ─────────────────────────────
 *   Net recognized revenue USD finance.logic.recognize_revenue.v1               FINANCE.LOGIC.RECOGNIZE_REVENUE               certified / finance-analytics
 *   Active commercial customers sales.datasets.commercial_customer_status_90d.v1 sales.datasets.commercial_customer_status_90d certified / sales-analytics
 *
 * ⚠  CROSS-PLATFORM BINDING GAP (must be resolved before production use)
 *    ─────────────────────────────────────────────────────────────────────
 *    finance.logic.recognize_revenue.v1          has a binding on: Snowflake (warehouse/prod)
 *    sales.datasets.commercial_customer_status_90d.v1 has a binding on: Databricks (prod)
 *
 *    No single runtime hosts both certified components.  Choose one of:
 *
 *      Option A – Snowflake execution (recommended once resolved)
 *        Register a Snowflake binding for sales.datasets.commercial_customer_status_90d.v1
 *        (e.g. via Delta Sharing → Snowflake, or a materialised mirror view).
 *        This query is written for Snowflake and is ready once that binding exists.
 *
 *      Option B – Databricks execution
 *        Register a Databricks binding for finance.logic.recognize_revenue.v1.
 *        Rewrite references to FINANCE.LOGIC.RECOGNIZE_REVENUE accordingly.
 *
 *    The placeholder reference below uses the Databricks canonical name for the
 *    customer status view; it must be replaced with the registered Snowflake binding.
 *
 * Deliberately NOT used
 * ─────────────────────
 *   FINANCE.DATASETS.INVOICE_REVENUE
 *     Registry lifecycle: retired.  Skips refunds/credit notes and applies no
 *     recognition-timing rules.  Superseded by the certified revenue path above.
 *
 *   SHARED.DATASETS.DIM_CUSTOMERS.IS_ACTIVE
 *     12-month order-activity flag.  Registry description explicitly states this is
 *     NOT the certified executive active-customer definition.
 *
 *   recommend_composition() returned SHARED.DATASETS.FACT_INVOICES for "recognized
 *   revenue" – overridden here.  That artifact's own registry description states that
 *   invoice dates/amounts alone do not constitute the certified recognized-revenue
 *   definition; the certified callable is finance.logic.recognize_revenue.v1.
 * ============================================================
 */

WITH

/* ──────────────────────────────────────────────────────────────
 * Reporting window: trailing 90 calendar days ending today.
 * Replace CURRENT_DATE with a bind variable / parameter to run
 * point-in-time snapshots (e.g. for month-end executive packs).
 * ────────────────────────────────────────────────────────────── */
date_window AS (
    SELECT
        CURRENT_DATE                                AS reporting_date,
        DATEADD('day', -90, CURRENT_DATE)           AS window_start
),

/* ──────────────────────────────────────────────────────────────
 * Net recognized revenue in USD – trailing 90-day window
 *
 * Reuses  : finance.logic.recognize_revenue.v1
 * Binding : FINANCE.LOGIC.RECOGNIZE_REVENUE  (Snowflake UDF, warehouse/prod)
 *           attribution_key: warehouse:snowflake:FINANCE.LOGIC.RECOGNIZE_REVENUE
 *
 * The UDF internally:
 *   1. Reads FINANCE.DATASETS.FACT_BILLABLE_EVENTS (invoices + refunds/credit
 *      notes, signed NET_AMOUNT, standardised across source systems).
 *   2. Retains only events whose recognition date falls within the window.
 *   3. Normalises each signed amount to USD via FINANCE.LOGIC.NORMALIZE_CURRENCY.
 *
 * Summing AMOUNT_USD here produces NET recognised revenue per customer because
 * refunds are already represented as negative signed amounts in the event stream.
 * ────────────────────────────────────────────────────────────── */
net_revenue AS (
    SELECT
        rev.CUSTOMER_ID,
        SUM(rev.AMOUNT_USD)                         AS net_recognized_revenue_usd
    FROM
        date_window                                 AS dw,
        TABLE(
            FINANCE.LOGIC.RECOGNIZE_REVENUE(
                dw.window_start,    -- recognition window start (inclusive)
                dw.reporting_date   -- recognition window end   (inclusive)
            )
        )                                           AS rev
    GROUP BY
        rev.CUSTOMER_ID
),

/* ──────────────────────────────────────────────────────────────
 * Active commercial customers as of the reporting date
 *
 * Reuses  : sales.datasets.commercial_customer_status_90d.v1
 * Binding : sales.datasets.commercial_customer_status_90d  (Databricks view, prod)
 *           attribution_key: databricks:sales.datasets.commercial_customer_status_90d
 *
 * IS_ACTIVE_COMMERCIAL_90D is the authoritative enterprise active-customer flag
 * used by all executive dashboards (lifecycle: certified, reuse_intent:
 * enterprise_canonical, owner: sales-analytics).
 *
 * ⚠ [BINDING GAP] The reference below uses the Databricks canonical name.
 *   Replace with the registered Snowflake binding before executing on the
 *   warehouse runtime (see header for resolution options).
 * ────────────────────────────────────────────────────────────── */
active_customers AS (
    SELECT
        CUSTOMER_ID
    FROM
        -- [BINDING GAP] replace with registered Snowflake binding when available
        sales.datasets.commercial_customer_status_90d
    WHERE
        IS_ACTIVE_COMMERCIAL_90D = TRUE
        AND REPORTING_DATE = (SELECT reporting_date FROM date_window)
),

/* ──────────────────────────────────────────────────────────────
 * Join revenue to the active-customer universe and aggregate.
 *
 * LEFT JOIN: customers who are active but had zero recognised revenue in the
 * trailing 90 days are still counted in the denominator – their $0 contribution
 * dilutes ARPAC, which is the correct economic interpretation.
 * ────────────────────────────────────────────────────────────── */
metric_inputs AS (
    SELECT
        (SELECT reporting_date FROM date_window)            AS reporting_date,
        (SELECT window_start   FROM date_window)            AS window_start,
        SUM(COALESCE(nr.net_recognized_revenue_usd, 0))    AS total_net_revenue_usd,
        COUNT(DISTINCT ac.CUSTOMER_ID)                      AS active_customer_count
    FROM
             active_customers  ac
        LEFT JOIN net_revenue  nr  ON nr.CUSTOMER_ID = ac.CUSTOMER_ID
)

/* ──────────────────────────────────────────────────────────────
 * Final ARPAC computation
 *
 * DIV0() is Snowflake-native: returns NULL (not an error) when
 * active_customer_count = 0, preventing divide-by-zero at month
 * boundaries or in filtered sub-populations.
 * ────────────────────────────────────────────────────────────── */
SELECT
    reporting_date,
    window_start,
    active_customer_count,
    total_net_revenue_usd,
    DIV0(
        total_net_revenue_usd,
        active_customer_count
    )                                                       AS arpac_usd
FROM
    metric_inputs
;
