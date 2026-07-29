# Trailing-90-Day ARPAC

Generated artifact: `arpac_trailing_90_day.sql`

The SQL creates a queryable Snowflake view named `shared.arpac_trailing_90_day` for executive reporting.

## Metric Definition

ARPAC is implemented as:

```text
net recognized revenue in USD over the trailing 90 days / active customers
```

Net recognized revenue is calculated as posted USD invoice revenue minus approved USD refunds in the same trailing 90-day window. The view returns the revenue window, gross invoice revenue, refund offsets, net recognized revenue, active-customer count, and the final ARPAC value.

## Reuse

Only artifacts from `/poc/scenarios/scenario-1a/workspace` were used:

- `shared.dim_customers`: reused for the active-customer definition via `is_active = TRUE`. The local DDL defines this as customers that placed at least one order in the last 12 months, so the denominator aligns with the executive-dashboard active-customer definition available in the workspace.
- `shared.fact_invoices`: reused for recognized gross revenue. `invoice_status = 'POSTED'` is treated as recognized invoice revenue.
- `shared.fact_refunds`: reused for recognized revenue offsets. `refund_status = 'APPROVED'` is subtracted from posted invoice revenue.

The workspace does not include an FX-rate or currency-conversion artifact, so the implementation reports USD ARPAC by filtering invoice and refund events to `currency_code = 'USD'`.