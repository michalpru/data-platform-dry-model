# Trailing-90-Day ARPAC Metric

Reusable executive reporting metric for **Average Revenue per Active Customer (ARPAC)** over the trailing 90 days. Built using only files under `registry-aware-authoring/scenarios/scenario-1c/workspace`.

## Output Files

| File | Purpose |
|------|---------|
| `arpac_trailing_90_days.sql` | Creates `finance.metrics.arpac_trailing_90_days` — the reusable Snowflake view. |
| `arpac_trailing_90_days.metric.yaml` | Dashboard-facing metric contract: formula, sources, columns, reuse notes, assumptions. |

---

## Metric Formula

```
ARPAC = net_recognized_revenue_usd / active_customer_count
```

| Component | Definition |
|-----------|-----------|
| `active_customer_count` | `COUNT(DISTINCT customer_id)` — customers with ≥ 1 POSTED invoice in the trailing 90 days |
| `net_recognized_revenue_usd` | Net USD recognized revenue from `FINANCE.LOGIC.RECOGNIZE_REVENUE` over the trailing 90 days, restricted to active customers only |

Revenue is **restricted to the active-customer denominator**: revenue from non-active customers is excluded from the numerator.

---

## What Was Reused

| Artifact | Reuse type | What was reused | Why this artifact |
|----------|-----------|----------------|-------------------|
| `sales.datasets.active_customer_90d` | Logic port | Active-customer rule: POSTED invoice in the trailing 90 days | This is the active-customer definition used by the executive trailing-90-day reporting layer. The metric inlines the single-date slice of this date-series view, adapting `date_sub` (Spark) to `DATEADD` (Snowflake) with identical semantics. |
| `FINANCE.LOGIC.RECOGNIZE_REVENUE` | Direct call | Net USD revenue via table function | Certified finance function that unions invoices and refunds/credit notes from `FACT_BILLABLE_EVENTS`, applies recognition timing, and converts all currencies to USD. No revenue or FX logic is re-implemented in the metric. |
| `FINANCE.LOGIC.NORMALIZE_CURRENCY` | Transitive | FX conversion to USD | Called internally by `RECOGNIZE_REVENUE`; reused transitively. Listed as a dependency for impact-analysis traceability. |
| `FINANCE.DATASETS.FACT_BILLABLE_EVENTS` | Transitive | Invoice + refund event source | Called internally by `RECOGNIZE_REVENUE`; nets POSTED invoices and APPROVED refunds via `IS_RECOGNIZABLE` and signed `NET_AMOUNT`. |

### What was NOT reused

| Artifact | Reason rejected |
|----------|----------------|
| `finance.invoice_revenue` (view) | Computes only POSTED invoice revenue; skips refunds and credit notes. Predates `recognize_revenue` and produces gross-only figures. |
| `marketing.logic.active_customer` (PySpark) | Marketing-portal login definition; not the commercial/enterprise active-customer rule. Also requires Databricks, incompatible with the Snowflake metric view. |
| `sales.datasets.commercial_customer_status_90d` | Depends on `sales.datasets.fact_commercial_events` and `sales.datasets.reporting_calendar`, neither of which exist in the shared DWH layer. |
| `shared.dim_customers.is_active` | 12-month order-activity flag — inconsistent with the 90-day trailing window required by the metric. |

---

## CTE Structure

```
active_customers          — POSTED invoices in trailing 90 days (from active_customer_90d rule)
        │
        └─► recognized_revenue   — calls FINANCE.LOGIC.RECOGNIZE_REVENUE(start, end),
                │                  filters to active customers, sums net USD revenue per customer
                │                        │
                │                  ┌─────┴──────────────────────────────────┐
                │             FACT_BILLABLE_EVENTS          NORMALIZE_CURRENCY
                │             (invoices + refunds)          (FX → USD)
                │
                └─► final SELECT  — aggregates to single metric_date-grain row
```

---

## Adoption Guidance

Executive dashboards should query `finance.metrics.arpac_trailing_90_days` directly. The view returns one row per day (snapshot at query time via `CURRENT_DATE()`) and exposes `active_customer_count` and `net_recognized_revenue_usd` alongside the final ratio for auditability.

```sql
SELECT
    metric_date,
    arpac_trailing_90_days_usd,
    net_recognized_revenue_usd,
    active_customer_count
FROM finance.metrics.arpac_trailing_90_days;
```

---

## Assumptions and Limitations

- **Active-customer window anchors on `invoice_date`** — consistent with `active_customer_90d`. Revenue recognition uses `RECOGNITION_DATE` (which may differ when `POSTED_DATE` is populated on the invoice). Both windows span the same 90-calendar-day range.
- **Revenue is already netted** — `RECOGNIZE_REVENUE` applies `IS_RECOGNIZABLE = TRUE` and uses signed `NET_AMOUNT` (negative for refunds), so no additional filtering is needed in the metric view.
- **Multi-currency** — `NORMALIZE_CURRENCY` inside `RECOGNIZE_REVENUE` converts all source currencies to USD using `dim_exchange_rates`. The metric view contains no currency-filtering logic.
- **Zero-customer guard** — ARPAC returns `NULL` (not zero) when `active_customer_count = 0` to avoid a misleading zero value.
- **Active customers with no trailing-90-day revenue** — included in the denominator (correctly diluting ARPAC) with a net revenue contribution of 0 via the LEFT JOIN.
- **Platform** — the metric view is Snowflake SQL. The source active-customer rule (`active_customer_90d`) is authored in Databricks/Spark SQL; the port uses `DATEADD(DAY, -90, ...)` which is semantically identical to Spark's `date_sub(..., 90)`.
