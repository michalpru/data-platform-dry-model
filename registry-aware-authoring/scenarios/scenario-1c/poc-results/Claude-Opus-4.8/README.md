# Trailing-90-Day ARPAC Metric

Reusable executive metric for **Average Revenue per Active Customer (ARPAC)** over the trailing 90 days, in USD. Built using only files under `registry-aware-authoring/scenarios/scenario-1c/workspace`.

## Deliverables

| File | Purpose |
|------|---------|
| `arpac_trailing_90_days.sql` | Snowflake view `finance.metrics.arpac_trailing_90_days` — the adoptable implementation. |
| `arpac_trailing_90_days.metric.yaml` | Governance/metric contract: formula, numerator/denominator, reuse notes, dependencies, assumptions. |

## Metric formula

```text
ARPAC = net_recognized_revenue_usd / active_customer_count
```

- **Grain:** one row per `metric_date` (as-of `CURRENT_DATE`).
- **Window:** trailing 90 days, `[CURRENT_DATE - 90, CURRENT_DATE]` inclusive — the same boundary convention as the reused active-customer definition.

## What was reused (and why)

| Artifact | Role | Reuse type | Why |
|----------|------|-----------|-----|
| `sales.datasets.active_customer_90d` | Denominator rule | Logic ported inline | The trailing-90-day active-customer definition already used by the executive/sales reporting layer (POSTED invoice in the last 90 days over `shared.dim_customers`). The metric inlines the single as-of slice of this per-`reporting_date` view, adapting Spark `date_sub` to Snowflake `DATEADD` (identical semantics). |
| `FINANCE.LOGIC.RECOGNIZE_REVENUE` | Numerator | Direct call | Certified function returning net recognized revenue in USD. It nets POSTED invoices against APPROVED refunds/credit notes and applies recognition timing — no revenue logic is duplicated. |
| `FINANCE.DATASETS.FACT_BILLABLE_EVENTS` | Numerator source | Transitive | The invoice + refund event table `RECOGNIZE_REVENUE` reads from (signed `NET_AMOUNT`, `IS_RECOGNIZABLE`). |
| `FINANCE.LOGIC.NORMALIZE_CURRENCY` | FX → USD | Transitive | Called inside `RECOGNIZE_REVENUE` to convert every source currency to USD via `dim_exchange_rates`. |

### What was NOT reused

| Artifact | Reason rejected |
|----------|----------------|
| `finance.invoice_revenue` | Gross POSTED-invoice revenue only; excludes refunds/credit notes, so not *net* recognized revenue. Superseded by `recognize_revenue`. |
| `sales.datasets.commercial_customer_status_90d` | Depends on `fact_commercial_events`, `reporting_calendar`, and `sales.datasets.dim_customers` — none exist in the workspace, so it is not runnable. |
| `marketing.logic.active_customer` | Marketing-portal login engagement (PySpark/Databricks) — a different semantic and platform than the commercial active-customer rule required here. |
| `shared.dim_customers.is_active` | 12-month order-activity flag — inconsistent with the required 90-day trailing window. |

## Numerator scope (active customers only)

Revenue in the numerator is restricted to the customers in the denominator: `RECOGNIZE_REVENUE` output is filtered to the `active_customers` set before aggregation, and the final aggregate is driven by a `LEFT JOIN` from `active_customers`. Revenue from non-active customers is therefore excluded, while active customers with zero trailing-90-day revenue remain in the denominator (contributing 0), correctly diluting ARPAC.

## Structure

```text
active_customers        -- denominator: POSTED invoice in trailing 90d (active_customer_90d rule)
      │
      └─► recognized_revenue  -- numerator: RECOGNIZE_REVENUE(start, end), net USD per customer,
              │                  filtered to active_customers
              │         ┌──────────────┴───────────────────┐
              │   FACT_BILLABLE_EVENTS            NORMALIZE_CURRENCY → DIM_EXCHANGE_RATES
              │   (invoices + refunds)            (FX → USD)
              │
              └─► final SELECT  -- COUNT(DISTINCT) denominator, SUM numerator, ARPAC ratio
```

## Adoption

Query the view directly; it exposes the numerator and denominator alongside the ratio for auditability.

```sql
SELECT
    metric_date,
    arpac_trailing_90_days_usd,
    net_recognized_revenue_usd,
    active_customer_count
FROM finance.metrics.arpac_trailing_90_days;
```

## Assumptions

- **Window anchors differ by design.** The denominator anchors on `invoice_date`; the numerator anchors on `RECOGNITION_DATE` (`COALESCE(POSTED_DATE, INVOICE_DATE)`) inside `RECOGNIZE_REVENUE`. Both span the same 90-day calendar range; recognition timing may shift an event between adjacent windows.
- **Revenue is already net.** `RECOGNIZE_REVENUE` returns only `IS_RECOGNIZABLE = TRUE` events with signed `NET_AMOUNT` (negative for refunds), so no extra netting is done in the metric.
- **Zero-customer guard.** ARPAC returns `NULL` (not 0) when `active_customer_count = 0`, via `NULLIF`.
- **Platform port.** The metric view is Snowflake SQL; the source `active_customer_90d` is Databricks/Spark SQL. `DATEADD(DAY, -90, ...)` is used in place of Spark `date_sub(..., 90)` with identical semantics.
