{# finance.logic.recognize_revenue.v1 — dbt macro binding (Snowflake dialect) #}
{# =========================================================================
   Reuse surface for the CERTIFIED revenue-recognition rule INSIDE dbt projects.

   This macro does NOT re-implement recognition or netting. It calls the certified
   Snowflake UDF (analytics.finance.fn_recognize_revenue) so dbt models reuse the exact
   same governed logic as raw-SQL and every other consumer.

   Registry view: finance.logic.recognize_revenue.v1 is ONE logical identity with two
   bindings on the Snowflake stack — the native UDF and this dbt macro. dbt gives reuse
   *inside* dbt; the registry records that the macro and the UDF are the same certified
   capability, so using either is not duplication.
   ========================================================================= #}
{% macro recognize_revenue(period_start, period_end) %}
    select *
    from table(
        {{ target.database }}.finance.fn_recognize_revenue({{ period_start }}, {{ period_end }})
    )
{% endmacro %}
