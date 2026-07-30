{% macro with_boolean_flag(column_expr, true_expr='true', false_expr='false') %}
  case when {{ column_expr }} then {{ true_expr }} else {{ false_expr }} end
{% endmacro %}