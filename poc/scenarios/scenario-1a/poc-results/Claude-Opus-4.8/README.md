# ARPAC (Trailing 90 Days) — Reusable Executive Metric

**ARPAC = Average Revenue per Active Customer**, over the trailing 90 days, in USD.

```
ARPAC = net_recognized_revenue_usd (numerator) / active_customer_count (denominator)
```

## Deliverables

| File | Purpose |
| --- | --- |
| `arpac_trailing_90_days.metric.yaml` | Reusable metric definition other executive dashboards adopt. |
| `arpac_trailing_90_days.sql` | Snowflake view `shared.metric_arpac_trailing_90_days` implementing the metric. |
| `README.md` | This file. |

## What was reused (and why)

Everything was built from the existing shared datasets in
`poc/scenarios/scenario-1a/workspace/dwh/shared/datasets`. No new datasets were
created — only a new reusable metric view.

| Reused artifact | Role in ARPAC | Why reused |
| --- | --- | --- |
| `shared.dim_customers.is_active` | **Denominator** — active-customer definition | This is the enterprise active-customer flag ("placed ≥ 1 order in the last 12 months") already used by other executive dashboards. Reusing it keeps ARPAC's denominator aligned with existing exec reporting instead of inventing a divergent definition. |
| `shared.fact_invoices` | **Numerator** — recognized revenue | Provides invoice amounts, status, currency, and customer link. |
| `shared.fact_refunds` | **Numerator** — refunds netted out | Provides refund amounts/status, linked to invoices via `invoice_id`. |

The only **new** artifact is the reusable view
`shared.metric_arpac_trailing_90_days`, which other dashboards can adopt with a
single `SELECT`.

## Definition details

**Denominator — active customers**
- `COUNT(DISTINCT customer_id)` from `shared.dim_customers` where `is_active = TRUE`.
- Uses the shared active-customer definition, unchanged.

**Numerator — net recognized revenue (USD)**
- Recognized revenue: `shared.fact_invoices` where `invoice_status = 'POSTED'`
  (DRAFT/VOID excluded), `currency_code = 'USD'`, and `invoice_date` in the
  trailing-90-day window.
- Refunds: `shared.fact_refunds` where `refund_status = 'APPROVED'`
  (PENDING/REJECTED excluded), `currency_code = 'USD'`, and `refund_date` in the
  trailing-90-day window.
- **Net** = recognized invoice revenue − approved refunds.
- **Active-customers-only:** both invoices and refunds are inner-joined to the
  active-customer set (refunds via their parent invoice's `customer_id`), so
  revenue from non-active customers is excluded, exactly as required.

**Time window**
- Trailing 90 days: `[CURRENT_DATE - 90 days, CURRENT_DATE)`.

## Assumptions

These follow from the column comments/values in the workspace DDL:

1. **Recognized** = `invoice_status = 'POSTED'` (DRAFT and VOID excluded).
2. **Net** subtracts only `refund_status = 'APPROVED'` refunds.
3. **USD scope:** the workspace has **no FX rate dataset**, so revenue is limited
   to rows already denominated in USD (`currency_code = 'USD'`). If multi-currency
   revenue must be included, add an FX-to-USD conversion step in front of the
   numerator; the metric structure does not otherwise change.
4. Invoices and refunds are each windowed by their own event date
   (`invoice_date` / `refund_date`).
5. Divide-by-zero is guarded with `NULLIF`; ARPAC is `NULL` when there are no
   active customers.

## How to adopt

```sql
SELECT arpac_trailing_90_days_usd
FROM shared.metric_arpac_trailing_90_days;
```

The view also exposes `as_of_date`, `window_start_date`,
`net_recognized_revenue_usd`, and `active_customer_count` for drill-down and
reconciliation.
