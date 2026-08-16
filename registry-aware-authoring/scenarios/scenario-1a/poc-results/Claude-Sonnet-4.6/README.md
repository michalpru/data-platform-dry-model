# Trailing-90-Day ARPAC Metric

Reusable executive reporting metric for **Average Revenue per Active Customer (ARPAC)** over the trailing 90 days. Built using only files under `registry-aware-authoring/scenarios/scenario-1a/workspace`.

## Output Files

| File | Purpose |
|------|---------|
| `arpac_trailing_90_days.sql` | Creates `shared.metric_arpac_trailing_90_days` — the reusable Snowflake view. |
| `arpac_trailing_90_days.metric.yaml` | Dashboard-facing metric contract: formula, sources, columns, assumptions. |

## What Was Reused

| Artifact | What was reused | Why |
|----------|----------------|-----|
| `shared.dim_customers.is_active` | Active-customer definition: placed ≥ 1 order in last 12 months | This flag is the only active-customer definition in the workspace and is already used by executive dashboards. No new classification logic was introduced. |
| `shared.fact_invoices` + `invoice_status = 'POSTED'` | Revenue recognition convention | POSTED is the recognised-revenue status across the shared schema. |
| `shared.fact_refunds` + `refund_status = 'APPROVED'` | Contra-revenue (refund deduction) | Joined via `fact_refunds.invoice_id → fact_invoices.invoice_id`, the only available join path. |

## Metric Formula

```
ARPAC = net_recognized_revenue_usd / active_customer_count
```

| Component | Definition |
|-----------|-----------|
| `active_customer_count` | `COUNT(DISTINCT customer_id)` from `shared.dim_customers` WHERE `is_active = TRUE` |
| `net_recognized_revenue_usd` | SUM of POSTED USD invoice amounts − SUM of APPROVED USD refund amounts, trailing 90 days, active customers only |

Revenue and refunds are **restricted to the active-customer denominator**: revenue from non-active customers is excluded from the numerator.

## CTE Structure

```
active_customer_denominator   — active customers (dim_customers.is_active = TRUE)
        │
        ├─► posted_revenue       — gross POSTED USD invoice amounts, trailing 90 days
        │
        ├─► approved_refunds     — APPROVED USD refunds on those invoices
        │
        └─► net_revenue_per_customer  — gross − refunds, one row per active customer
                    │
                    └─► final SELECT  — aggregates to metric_date-grain scalar
```

## Adoption Guidance

Executive dashboards should query `shared.metric_arpac_trailing_90_days` directly. The view returns one row per day (snapshot at query time) and exposes `active_customer_count` and `net_recognized_revenue_usd` alongside the final ratio for auditability.

```sql
SELECT
    metric_date,
    arpac_trailing_90_days_usd,
    net_recognized_revenue_usd,
    active_customer_count
FROM shared.metric_arpac_trailing_90_days;
```

## Assumptions and Limitations

- **USD only** — `currency_code = 'USD'` is applied to both invoices and refunds. No exchange-rate or FX conversion table exists in this workspace; multi-currency invoices are excluded rather than incorrectly summed.
- **Active-customer definition** — `dim_customers.is_active` (12-month order activity) is the only available definition. In a governed data platform, this would be replaced by a certified commercial-activity dataset that could differ from the 12-month flag.
- **Zero-customer guard** — ARPAC returns `NULL` (not zero) when `active_customer_count = 0` to avoid a misleading zero value.
- **Customers with no trailing-90-day revenue** — included in the denominator (correctly diluting ARPAC) with a net revenue contribution of 0.
