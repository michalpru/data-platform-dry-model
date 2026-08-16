# Trailing-90-Day ARPAC Metric

This deliverable defines a reusable executive reporting metric for trailing-90-day Average Revenue per Active Customer (ARPAC), using only files under `registry-aware-authoring/scenarios/scenario-1a/workspace`.

## Output Files

- `arpac_trailing_90_days.sql` creates `shared.metric_arpac_trailing_90_days`.
- `arpac_trailing_90_days.metric.yaml` provides the dashboard-facing metric contract.

## Reuse

The metric reuses the shared customer definition from `shared.dim_customers`. The denominator is the distinct count of customers where `is_active = TRUE`, matching the available active-customer definition documented in the workspace DDL as customers who placed at least one order in the last 12 months.

The metric reuses `shared.fact_invoices` for recognized revenue and treats `invoice_status = 'POSTED'` as recognized invoice revenue. It reuses `shared.fact_refunds` for contra-revenue and treats `refund_status = 'APPROVED'` as recognized refunds.

## Metric Logic

ARPAC is calculated as:

```text
net_recognized_revenue_usd / active_customer_count
```

Where:

- `active_customer_count` is `COUNT(DISTINCT customer_id)` from `shared.dim_customers` where `is_active = TRUE`.
- `net_recognized_revenue_usd` is posted USD invoice revenue minus approved USD refunds in the trailing 90 days.
- Revenue and refunds are restricted to customers in the active-customer denominator.

## Adoption Guidance

Executive dashboards should consume `shared.metric_arpac_trailing_90_days` directly or implement the YAML contract exactly. The view emits the metric as of `CURRENT_DATE`, with numerator and denominator components included for auditability.

## Assumptions

- USD-only revenue is filtered with `currency_code = 'USD'` because no exchange-rate or currency conversion artifact exists in the allowed workspace scope.
- Refund customer attribution is derived through `shared.fact_refunds.invoice_id` joined to `shared.fact_invoices.invoice_id`.
- The ARPAC value is `NULL` when there are no active customers, preventing divide-by-zero behavior.