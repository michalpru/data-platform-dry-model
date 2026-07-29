-- Snowflake SQL
-- Trailing-90-day ARPAC: net recognized revenue in USD / active customers.
-- Call example:
--   SELECT * FROM TABLE(finance.arpac_trailing_90_day('2026-07-29'::DATE));

CREATE OR REPLACE FUNCTION finance.arpac_trailing_90_day(as_of_date DATE)
RETURNS TABLE (
    metric_name              VARCHAR,
    period_start_date        DATE,
    period_end_date          DATE,
    net_recognized_revenue_usd NUMBER(18,2),
    active_customers         NUMBER(38,0),
    arpac_usd                NUMBER(18,2)
)
AS
$$
    WITH reporting_period AS (
        SELECT
            DATEADD(day, -90, as_of_date) AS period_start_date,
            as_of_date                    AS period_end_date
    ),

    invoice_revenue AS (
        SELECT
            revenue_date,
            invoice_revenue_usd
        FROM finance.invoice_revenue
        CROSS JOIN reporting_period
        WHERE revenue_date >= period_start_date
          AND revenue_date <= period_end_date
    ),

    refund_revenue AS (
        SELECT
            r.refund_date,
            nc.converted_amount AS refund_revenue_usd
        FROM shared.fact_refunds AS r
        JOIN shared.fact_invoices AS i
          ON i.invoice_id = r.invoice_id
        CROSS JOIN reporting_period
        CROSS JOIN TABLE(finance.normalize_currency(
            r.refund_amount,
            r.currency_code,
            'USD',
            CAST(r.refund_date AS DATE)
        )) AS nc
        WHERE r.refund_status = 'APPROVED'
          AND r.refund_date >= period_start_date
          AND r.refund_date <= period_end_date
    ),

    net_recognized_revenue AS (
        SELECT
            COALESCE((SELECT SUM(invoice_revenue_usd) FROM invoice_revenue), 0)
          - COALESCE((SELECT SUM(refund_revenue_usd) FROM refund_revenue), 0)
            AS net_recognized_revenue_usd
    ),

    active_customers AS (
        SELECT COUNT(DISTINCT customer_id) AS active_customer_count
        FROM marketing.customer_logins
        CROSS JOIN reporting_period
        WHERE application_name = 'Marketing Portal'
          AND CAST(login_timestamp AS DATE) >= period_start_date
          AND CAST(login_timestamp AS DATE) <= period_end_date
    )

    SELECT
        'trailing_90_day_arpac' AS metric_name,
        rp.period_start_date,
        rp.period_end_date,
        ROUND(nrr.net_recognized_revenue_usd, 2) AS net_recognized_revenue_usd,
        ac.active_customer_count AS active_customers,
        ROUND(nrr.net_recognized_revenue_usd / NULLIF(ac.active_customer_count, 0), 2) AS arpac_usd
    FROM reporting_period AS rp
    CROSS JOIN net_recognized_revenue AS nrr
    CROSS JOIN active_customers AS ac
$$;