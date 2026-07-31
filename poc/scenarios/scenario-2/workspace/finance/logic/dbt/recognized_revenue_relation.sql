{% macro recognized_revenue_relation(start_date_expression, end_date_expression) %}
  {# finance.logic.recognize_revenue.v1 — dbt macro binding (Snowflake dialect) #}
  {# Reuse surface for the CERTIFIED revenue-recognition rule INSIDE dbt projects. It reads the
     canonical billable-event stream (fact_billable_events) and reuses normalize_currency, so a
     dbt model reuses the exact same governed logic as the native UDF
     FINANCE.LOGIC.RECOGNIZE_REVENUE. The registry records that this macro and the UDF are ONE
     certified capability, so using either is not duplication. #}
(
    SELECT
        b.customer_id,
        b.billable_event_id,
        b.recognition_date,
        b.event_type,
        b.currency_code AS source_currency,
        ROUND(
            {{ normalize_currency(
                'b.net_amount',
                'b.currency_code',
                "'USD'",
                'b.recognition_date'
            ) }},
            2
        ) AS recognized_revenue_usd
    FROM {{ ref('fact_billable_events') }} AS b
    WHERE b.recognition_date BETWEEN {{ start_date_expression }} AND {{ end_date_expression }}
      AND b.is_recognizable = TRUE
)
{% endmacro %}
