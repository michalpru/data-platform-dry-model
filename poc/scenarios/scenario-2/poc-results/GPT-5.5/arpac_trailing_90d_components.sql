{{ config(materialized='view') }}

{% set reporting_date_expression = "TO_DATE(" ~ var('arpac_reporting_date', 'CURRENT_DATE') ~ ")" %}
{% set start_date_expression = "DATEADD(day, -89, " ~ reporting_date_expression ~ ")" %}

WITH active_customer_denominator AS (
    SELECT
        customer_id
    FROM sales.datasets.commercial_customer_status_90d
    WHERE reporting_date = {{ reporting_date_expression }}
      AND is_active_commercial_90d = TRUE
    GROUP BY customer_id
),

recognized_revenue_90d AS (
    SELECT
        customer_id,
        recognized_revenue_usd
    FROM {{ dry_finance_macros.recognized_revenue_relation(start_date_expression, reporting_date_expression) }}
),

active_customer_revenue AS (
    SELECT
        r.customer_id,
        SUM(r.recognized_revenue_usd) AS recognized_revenue_usd_90d
    FROM recognized_revenue_90d AS r
    INNER JOIN active_customer_denominator AS a
        ON r.customer_id = a.customer_id
    GROUP BY r.customer_id
)

SELECT
    {{ reporting_date_expression }} AS reporting_date,
    COALESCE(SUM(active_customer_revenue.recognized_revenue_usd_90d), 0) AS net_recognized_revenue_usd_90d,
    COUNT(DISTINCT active_customer_denominator.customer_id) AS active_customer_count,
    COALESCE(SUM(active_customer_revenue.recognized_revenue_usd_90d), 0)
        / NULLIF(COUNT(DISTINCT active_customer_denominator.customer_id), 0) AS arpac_usd_trailing_90d
FROM active_customer_denominator
LEFT JOIN active_customer_revenue
    ON active_customer_denominator.customer_id = active_customer_revenue.customer_id;