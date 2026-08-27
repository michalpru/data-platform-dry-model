# Trailing 90-Day ARPAC Metric

This directory contains a reusable ARPAC metric definition for executive reporting.

## Delivered artifacts

- `arpac_trailing_90_days.metric.yaml` defines the business metric, formula, grain, dependencies, filters, and validation rules.
- `arpac_trailing_90_days.sql` provides a reusable SQL view implementation for dashboard adoption.

## Metric definition

ARPAC is defined as:

```text
net_recognized_revenue_usd_90d / active_customer_count_90d
```

The grain is `reporting_date`.

The trailing window follows the inclusive convention already present in the current active-customer executive-dashboard definition: `reporting_date - 90 days` through `reporting_date`.

## Reuse decisions

The denominator reuses `sales.datasets.active_customer_90d`. That view is the local trailing-90-day active-customer definition and is the best match for the requirement to align with other executive dashboards.

The numerator reuses `FINANCE.LOGIC.RECOGNIZE_REVENUE`. That function returns recognized revenue in USD for a supplied date range and already incorporates `FINANCE.DATASETS.FACT_BILLABLE_EVENTS`, including invoices and refunds, and `FINANCE.LOGIC.NORMALIZE_CURRENCY` for USD conversion.

The metric implementation joins recognized revenue back to the active-customer denominator by `reporting_date` and `customer_id`. This ensures revenue from non-active customers is excluded from the numerator.

## Adoption contract

Dashboard consumers should group or filter by `reporting_date` and use:

- `arpac_usd_90d` as the published metric value.
- `net_recognized_revenue_usd_90d` as the numerator audit measure.
- `active_customer_count_90d` as the denominator audit measure.

