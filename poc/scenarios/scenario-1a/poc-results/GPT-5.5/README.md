# Trailing 90 Day ARPAC

This folder contains a reusable ARPAC metric definition for executive dashboards:

- `arpac_trailing_90_day_metric.yaml` defines the metric contract, numerator, denominator, source reuse, and dashboard adoption guidance.
- `arpac_trailing_90_day.sql` implements the metric in Snowflake SQL using only the shared datasets in `poc/scenarios/scenario-1a/workspace`.

## Metric

ARPAC is calculated as:

```text
net recognized revenue in USD over the trailing 90 days / distinct active customers
```

The query returns `NULL` for ARPAC when the active-customer denominator is zero.

## Reuse

The definition reuses the local shared data assets:

- `shared.dim_customers`: reuses `customer_id` and `is_active` for the denominator. The source DDL documents `is_active` as customers who placed at least one order in the last 12 months, which is the active-customer definition available to this scenario workspace.
- `shared.fact_invoices`: reuses posted invoice facts as recognized gross revenue. The metric includes only `invoice_status = 'POSTED'` and `currency_code = 'USD'`.
- `shared.fact_refunds`: reuses approved refund facts as contra revenue. Refunds are joined to invoices to inherit `customer_id`, and the metric includes only `refund_status = 'APPROVED'` and `currency_code = 'USD'`.

## Customer Scope

The numerator is restricted to the denominator customer set. Both invoice revenue and refund contra revenue join to the `active_customers` CTE before aggregation, so revenue from non-active customers is excluded.

## Reporting Window

Dashboards should bind `:as_of_date` to the reporting date. The trailing 90-day window is inclusive: `DATEADD(day, -89, as_of_date)` through `as_of_date`.
