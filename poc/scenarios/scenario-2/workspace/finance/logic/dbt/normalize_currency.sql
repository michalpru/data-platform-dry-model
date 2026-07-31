{% macro normalize_currency(amount_expression, source_currency_expression, target_currency_expression, conversion_date_expression) %}
  {# finance.logic.normalize_currency.v1 — dbt macro binding (Snowflake dialect) #}
  {# Reuse surface for the certified currency rule INSIDE dbt projects. It resolves to the same
     FX table (dim_exchange_rates), join grain and rounding as the Snowflake table function
     FINANCE.LOGIC.NORMALIZE_CURRENCY, so a dbt model reuses the exact same governed rule. #}
(
    {{ amount_expression }} *
    COALESCE(
        (
            SELECT fx.exchange_rate
            FROM {{ ref('dim_exchange_rates') }} AS fx
            WHERE fx.from_currency = {{ source_currency_expression }}
              AND fx.to_currency = {{ target_currency_expression }}
              AND fx.rate_date = {{ conversion_date_expression }}
        ),
        CASE
            WHEN {{ source_currency_expression }} = {{ target_currency_expression }}
                THEN 1
        END
    )
)
{% endmacro %}
