# Trailing 90 Day ARPAC Metric

This directory contains a reusable ARPAC metric definition for executive reporting:

- `arpac_trailing_90_day_metric.yaml` is the portable metric contract.
- `arpac_trailing_90_day.sql` is a Snowflake-style reference implementation.

## Metric Definition

ARPAC is defined as:

```text
net_recognized_revenue_usd / active_customer_count
```

The numerator is posted invoice revenue in USD minus approved refunds in USD over the trailing 90 days. Both invoice revenue and refunds are restricted to the customers in the denominator, so revenue from non-active customers is excluded.

The denominator is the distinct count of active customers produced by the existing active-customer definition used for executive dashboards.

## Reuse Summary

- Reused `marketing-domain/marketing/logic/active_customer.py` for the denominator definition: distinct customers with a Marketing Portal login between `as_of_date - trailing_days` and `as_of_date`, using the existing default `trailing_days = 90`.
- Reused `finance-domain/finance/datasets/invoice_revenue.sql` for posted invoice revenue that is already recognized and converted to USD.
- Reused `dwh/shared/datasets/fact_refunds.sql` to subtract approved refunds from recognized revenue.
- Reused the currency conversion rule from `finance-domain/finance/logic/normalize_currency.sql`: join exchange rates by source currency, USD target currency, and conversion date, then round converted amounts to two decimals.

## Implementation Notes

The scenario workspace contains the PySpark active-customer function but not the customer-login source table. For that reason, the SQL reference implementation expects `analytics.active_customers` to be materialized upstream from `marketing.logic.active_customer` with the same `as_of_date` and `trailing_days` parameters used by the metric.

Refunds are attributed to customers by joining `shared.fact_refunds.invoice_id` to `shared.fact_invoices.invoice_id`. Only `APPROVED` refunds inside the trailing window are subtracted.

When there are no active customers, `arpac_usd` returns `NULL` rather than dividing by zero.