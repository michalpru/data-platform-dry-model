# Trailing-90-Day ARPAC Metric

This result contains a queryable Snowflake SQL implementation of executive-reporting ARPAC in `arpac_trailing_90_day.sql`.

## Metric definition

ARPAC is calculated as:

```text
net recognized revenue in USD / active customers
```

For a supplied `as_of_date`, the function evaluates the trailing 90-day window from `DATEADD(day, -90, as_of_date)` through `as_of_date`, inclusive.

## Reuse decisions

- Reused `finance.invoice_revenue` for recognized posted invoice revenue in USD. This preserves the existing invoice-status filter, exchange-rate join, and USD rounding logic already defined by Finance.
- Reused `finance.normalize_currency` for refund currency conversion to USD instead of duplicating exchange-rate logic.
- Reused `shared.fact_refunds` and `shared.fact_invoices` to subtract approved refunds from recognized invoice revenue.
- Aligned the active-customer denominator with `marketing.logic.active_customer`: distinct customers with `application_name = 'Marketing Portal'` and login activity inside the trailing 90-day window.

## Query example

```sql
SELECT *
FROM TABLE(finance.arpac_trailing_90_day('2026-07-29'::DATE));
```

## Assumptions

- `marketing.customer_logins` is the SQL-accessible dataset corresponding to the DataFrame consumed by `marketing.logic.active_customer`.
- Approved refunds reduce recognized revenue on `refund_date` and are converted using the refund currency and refund date.
- The trailing 90-day period is inclusive of both the start date and `as_of_date`, matching the active-customer implementation's inclusive date filters.