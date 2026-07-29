# ARPAC Metric – Trailing 90 Days
**Scenario:** 1a  
**Model:** Claude Sonnet 4.6  
**Output file:** `metric_arpac_trailing_90d.sql`

---

## What was built

A queryable Snowflake SQL implementation of **ARPAC (Average Revenue per Active Customer)** over a rolling 90-day window, intended for executive reporting.

$$\text{ARPAC} = \frac{\text{Net Recognized Revenue (USD)}}{\text{Active Customers}}$$

---

## Reuse inventory

| Artifact | Location | What was reused |
|---|---|---|
| `shared.dim_customers` | `dwh/shared/datasets/dim_customers.sql` | Table reference + **`is_active` flag** for the active-customer denominator |
| `shared.fact_invoices` | `dwh/shared/datasets/fact_invoices.sql` | `invoice_amount`, `invoice_status`, `invoice_date`, `currency_code` for gross revenue |
| `shared.fact_refunds` | `dwh/shared/datasets/fact_refunds.sql` | `refund_amount`, `refund_status`, `refund_date`, `currency_code` for deductions |
| **Active-customer definition** | DDL comment in `dim_customers.sql` | `is_active = TRUE` ↔ "placed ≥ 1 order in the last 12 months" — same definition already used in other executive dashboards |

No new tables or functions were created. All source objects come from `dwh/shared/`, the governed shared layer of the workspace.

---

## Metric logic

### Numerator – Net Recognized Revenue (USD)

```
Net Revenue = SUM(invoice_amount WHERE status='POSTED' AND currency='USD' AND date in window)
            - SUM(refund_amount  WHERE status='APPROVED' AND currency='USD' AND date in window)
```

- **POSTED** invoices represent recognized revenue; DRAFT and VOID are excluded.  
- **APPROVED** refunds are deducted; PENDING and REJECTED are excluded.  
- The refund window uses `refund_date` (when the refund was approved), not the originating invoice date.

### Denominator – Active Customers

```
Active Customers = COUNT(customer_id) WHERE is_active = TRUE
```

- Sourced directly from `dim_customers.is_active`, which encodes the existing executive-dashboard definition: a customer who placed at least one order in the last 12 months.
- The 12-month activity window for the denominator is intentionally broader than the 90-day revenue window; this matches how ARPAC is typically interpreted (base of engaged customers, not just buyers in the current period).

### Trailing window

- `DATEADD(DAY, -90, CURRENT_DATE)` through `CURRENT_DATE` — re-evaluated at query runtime so no date parameter is needed for scheduled execution.

---

## Assumptions and constraints

| # | Assumption | Impact if wrong |
|---|---|---|
| 1 | No FX-conversion table exists in the workspace; only `currency_code = 'USD'` rows are included | Multi-currency revenue is silently excluded; addresses ~0% of revenue if customers are USD-only, otherwise understates ARPAC |
| 2 | `POSTED` = recognized revenue; `VOID`/`DRAFT` are not recognized | Adjust `invoice_status` filter if the accounting definition differs |
| 3 | Refunds are netted by `refund_date` within the window | If period-matching to invoice date is required, add a join to `fact_invoices` and filter by `invoice_date` |
| 4 | `dim_customers.is_active` is kept current by an upstream process | Stale data in the dimension will distort the denominator |

---

## Query output columns

| Column | Type | Description |
|---|---|---|
| `window_start_date` | DATE | First day of the 90-day window |
| `window_end_date` | DATE | Last day of the window (today) |
| `total_net_revenue_usd` | NUMBER(18,2) | Gross POSTED invoices minus APPROVED refunds, USD |
| `total_active_customers` | INTEGER | Count of customers where `is_active = TRUE` |
| `arpac_usd` | NUMBER(18,2) | Net revenue ÷ active customers; NULL if denominator = 0 |
