# Trailing-90-Day ARPAC Metric

This output implements `executive.arpac_trailing_90_day` in Snowflake SQL.

## Reused workspace artifacts

- `shared.fact_invoices`: reused as the source of posted invoice revenue. Only `invoice_status = 'POSTED'` invoices inside the trailing 90-day reporting window are included.
- `shared.fact_refunds`: reused as the source of refund and credit-note offsets. Only `refund_status = 'APPROVED'` refunds inside the trailing 90-day reporting window are subtracted from revenue.
- `shared.dim_customers.is_active`: reused as the active-customer definition because the dataset documents this as customers that placed at least one order in the last 12 months, matching the executive-dashboard active-customer definition available in the allowed workspace.

## Metric definition

`ARPAC_90D_USD = trailing_90_day_net_recognized_revenue_usd / active_customer_count`

Net recognized revenue is posted invoice revenue less approved refunds and credit notes.

## USD conversion handling

The allowed workspace has `currency_code` on invoices and refunds, and explicitly notes that invoices are not necessarily in USD. It does not contain an FX-rate table, currency-conversion function, or preconverted USD revenue dataset.

To avoid reporting an overstated or understated executive metric, the SQL computes `arpac_90d_usd` only when every recognized revenue event in the trailing window is already in USD. If non-USD revenue exists, the view remains queryable but returns:

- `arpac_90d_usd = NULL`
- `metric_status = 'BLOCKED_MISSING_FX_REUSE'`
- `non_usd_revenue_event_count` and `non_usd_currency_codes` for remediation

Once a governed FX conversion artifact is added to the workspace, the `recognized_revenue_events` CTE should be extended to convert each revenue event into USD before aggregation.
