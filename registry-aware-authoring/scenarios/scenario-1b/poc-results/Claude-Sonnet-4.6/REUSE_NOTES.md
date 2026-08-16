# ARPAC Metric — Reuse Notes

## What Was Built

`metrics.arpac_trailing_90d` — a Snowflake view that computes trailing-90-day
Average Revenue Per Active Customer (ARPAC) for executive reporting.

**Formula:**
```
ARPAC = Net Recognized Revenue (USD) / Active Customer Count
```

---

## Reuse Decision Log

### [R1] `finance.invoice_revenue` (VIEW) — reused directly

**File:** `finance-domain/finance/datasets/invoice_revenue.sql`

The view already encodes:
- POSTED-only invoice filter (`WHERE invoice_status = 'POSTED'`)
- FX conversion to USD via `finance.dim_exchange_rates`
- Rounding convention: `ROUND(amount * rate, 2)`

`arpac_metric.sql` queries this view and adds only a date-window predicate.
None of the FX join logic or status filter was re-implemented.

---

### [R2] `finance.dim_exchange_rates` (TABLE) — reused for refund FX conversion

**File:** `finance-domain/finance/datasets/dim_exchange_rates.sql`

The APPROVED-refund FX conversion in `arpac_metric.sql` applies the identical
join pattern already established by `finance.invoice_revenue` and
`finance.normalize_currency`:

```sql
JOIN finance.dim_exchange_rates AS fx
  ON  fx.from_currency = r.currency_code
  AND fx.to_currency   = 'USD'
  AND fx.rate_date     = r.refund_date
```

This ensures refund FX conversion is consistent with invoice FX conversion.

---

### [R3] `marketing/logic/active_customer.py` (PySpark logic) — translated to SQL verbatim

**File:** `marketing-domain/marketing/logic/active_customer.py`

This is the authoritative active-customer definition used by other executive
dashboards. Every criterion was translated directly:

| Python | SQL equivalent |
|--------|---------------|
| `application_name == "Marketing Portal"` | `WHERE application_name = 'Marketing Portal'` |
| `window_start = date_sub(as_of, 90)` | `DATEADD(day, -90, CURRENT_DATE)` |
| `login_timestamp >= window_start` | `CAST(login_timestamp AS DATE) >= DATEADD(day, -90, CURRENT_DATE)` |
| `login_timestamp <= as_of` | `CAST(login_timestamp AS DATE) <= CURRENT_DATE` |
| `.select("customer_id").distinct()` | `COUNT(DISTINCT customer_id)` |

The `trailing_days=90` default from the function signature is used as the
window size, matching the "trailing-90-day ARPAC" requirement.

**Why this matters:** using any other active-customer definition would produce
an ARPAC figure that is not comparable to the active-customer counts already
shown in executive dashboards, undermining the metric's credibility.

---

### [R4] `shared.fact_refunds` (TABLE) — reused directly

**File:** `dwh/shared/datasets/fact_refunds.sql`

Sourced from the shared DWH layer. Only `APPROVED` refunds are included;
`PENDING` and `REJECTED` refunds are excluded from recognized revenue.

---

## What Was Not Reused (and Why)

| Artifact | Reason not used |
|----------|----------------|
| `shared.dim_customers.is_active` | Defined as "placed ≥ 1 order in last 12 months" — a purchase-based activity signal. The executive dashboard active-customer definition (R3) uses login-based activity on a 90-day window, which is the correct denominator for this metric. |
| `finance.normalize_currency` (function) | The table-valued function interface requires calling `TABLE(normalize_currency(...))` per row; using the FX table directly (same pattern as `invoice_revenue`) is simpler and consistent. |

---

## Assumptions

1. `marketing.customer_logins` exists with columns:
   `customer_id`, `login_timestamp`, `application_name`
2. Exchange rates are available in `finance.dim_exchange_rates` for every
   `(currency_code, refund_date)` pair in `fact_refunds`. Refunds without a
   matching rate are silently excluded (same behaviour as `invoice_revenue`
   for invoices).
3. The view is evaluated with `CURRENT_DATE` as the as-of date. For point-in-
   time reporting, parameterise `CURRENT_DATE` with a bind variable.
