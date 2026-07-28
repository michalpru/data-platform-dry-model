# ARPAC Trailing-90-Day Metric — PoC Result

**Model:** Claude Opus 4.8
**Scenario:** 1-A — trailing-90-day ARPAC for executive reporting
**Engine:** Snowflake SQL
**Constraint:** only assets in `poc/scenarios/scenario-1a/workspace` were used

---

## Output

| File | Purpose |
|------|---------|
| `metric_arpac_trailing_90d.sql` | Queryable Snowflake SQL implementation of the metric |

`ARPAC = net recognized revenue (USD) / number of active customers`

---

## What the workspace exposes

```
workspace/dwh/shared/
├── datasets/
│   ├── dim_customers.sql   -- has is_active (12-month order flag)
│   ├── fact_invoices.sql   -- POSTED/DRAFT/VOID; currency NOT necessarily USD
│   └── fact_refunds.sql    -- APPROVED/PENDING/REJECTED refunds & credit notes
└── metrics/                -- empty (no enterprise metric definitions here)
```

There are **no** enterprise definitions for *recognized revenue* or *active customer*
and **no** FX-rate table. The metric is therefore authored from the base tables.

---

## What was reused (and why)

### 1. `shared.dim_customers.is_active` — active-customer definition *(reused as-is)*
- The requirement is that the denominator be **aligned with other executive dashboards**.
  Per the DDL comment, `is_active` means *"placed ≥ 1 order in the last 12 months"* and
  is the flag those dashboards already use, so joining on it keeps ARPAC comparable by
  construction. No new "active" definition was invented.

### 2. `shared.fact_invoices` — gross recognized revenue *(reused, filtered)*
- Filtered to `invoice_status = 'POSTED'` (DRAFT/VOID excluded), taken directly from the
  status vocabulary in the DDL.

### 3. `shared.fact_refunds` — refund / credit-note netting *(reused, filtered)*
- The DDL comment states *"net recognized revenue must subtract approved refunds/credit
  notes from gross invoice amounts."* The query joins refunds back to `fact_invoices`,
  keeps only `APPROVED`, and subtracts them — so revenue is **net**, not gross. Ignoring
  this table (a common shortcut) would overstate revenue.

---

## Design decisions

| Decision | Rationale |
|----------|-----------|
| Denominator = `COUNT(*) WHERE is_active = TRUE` | Reuses the dashboard definition verbatim; the flag is intentionally **not** re-windowed to 90 days so it stays comparable to other executive reports. |
| Numerator windowed to trailing 90 days | `invoice_date >= CURRENT_DATE - 90`; refunds scoped to the same POSTED-invoice cohort via join, so gross and refund adjustments refer to the same transactions. |
| Net revenue = POSTED invoices − APPROVED refunds | Follows the explicit instruction in `fact_refunds.sql`. |
| `NULL` guard on `arpac_usd` | Avoids divide-by-zero and signals a data-quality issue when there are no active customers. |
| `COALESCE(..., 0)` on revenue CTEs | Prevents `NULL` propagation on an empty window. |

---

## Currency: a known gap, surfaced rather than hidden

`fact_invoices` / `fact_refunds` are **not necessarily in USD**, and this workspace has
**no FX-rate table**. Summing mixed currencies as if they were USD would be wrong, so the
implementation:

1. restricts revenue to `currency_code = 'USD'` (a defensible USD figure), and
2. emits `usd_invoice_coverage_pct` — the share of trailing-90-day POSTED invoice value
   that was actually USD. If that is materially below `100.00`, non-USD revenue was
   dropped and **the metric is incomplete until an FX table is added**.

The SQL includes a documented pattern for the multi-currency version (join a
`shared.fx_rates` table and convert before aggregating). That table does not exist in the
workspace, so it was intentionally left out rather than fabricated.

---

## Honest limitations (inherent to Scenario 1A)

Even with the reuse above, this metric is **not guaranteed comparable to a governed
enterprise ARPAC**, because the workspace contains no authoritative definitions:

1. **Revenue recognition** — only a `POSTED`/refund netting rule is available here. Any
   enterprise revenue-recognition logic (deferrals, allocations, etc.) is not present and
   is not applied.
2. **Currency** — no FX table; non-USD revenue is excluded and reported via the coverage
   diagnostic rather than converted.
3. **Active customer** — `is_active` is a 12-month order flag. If the certified executive
   definition is actually a 90-day commercial-activity rule, the denominator would differ;
   this implementation deliberately matches the flag the dashboards use today.

These are limits of what is discoverable in this workspace, not choices to paper over —
they are surfaced so a reviewer can decide whether the number is fit for executive use.
