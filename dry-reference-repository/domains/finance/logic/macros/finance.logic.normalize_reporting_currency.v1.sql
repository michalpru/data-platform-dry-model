{% macro normalize_reporting_currency(amount_expr, currency_expr, as_of_date_expr, reporting_currency="'USD'") %}
  -- finance.logic.normalize_reporting_currency.v1  (callable logic — SQL macro)
  -- Domain: finance | Lifecycle: shared | Owner: finance-analytics
  --
  -- Currency rule: convert {{ amount_expr }} from its source currency to the
  -- enterprise reporting currency using the daily FX rate effective on
  -- {{ as_of_date_expr }}. Amounts already in the reporting currency pass through
  -- at rate 1.0. Centralizing this rule prevents each team from hardcoding its own
  -- FX table, join grain, or rounding convention.
  ROUND(
    {{ amount_expr }} * COALESCE(
      (
        SELECT fx.rate_to_reporting
        FROM finance.raw.fx_rates AS fx
        WHERE fx.from_currency = {{ currency_expr }}
          AND fx.to_currency   = {{ reporting_currency }}
          AND fx.rate_date     = {{ as_of_date_expr }}
      ),
      CASE WHEN {{ currency_expr }} = {{ reporting_currency }} THEN 1.0 ELSE NULL END
    ),
    2
  )
{% endmacro %}
