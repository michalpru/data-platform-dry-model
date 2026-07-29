# ARPAC (trailing 90-day) — reuse notes

**Deliverable:** [`arpac_90d.sql`](arpac_90d.sql) — a queryable Snowflake view `finance.arpac_90d`.

**Metric:**

```
ARPAC(90d) = net recognized revenue in USD (trailing 90d) / number of active customers (trailing 90d)
```

Only artifacts under `poc/scenarios/scenario-1b/workspace/` were used.

---

## What was reused

| Component | Artifact reused | Why |
|---|---|---|
| Gross recognized revenue (USD) | `finance.invoice_revenue` | Working view that already normalizes each POSTED invoice to USD via `dim_exchange_rates`. Reused rather than re-deriving currency conversion. |
| Refunds source | `shared.fact_refunds` | Needed to turn *gross* revenue into *net* revenue. Only `APPROVED` refunds are subtracted. |
| Currency conversion for refunds | `finance.normalize_currency` | Shared FX utility. Reused via a `LATERAL` call so refund→USD conversion stays DRY and consistent with the platform, instead of re-writing an exchange-rate join. |
| Active-customer source | `shared.fact_invoices` | Commercial activity (a POSTED invoice) in the trailing 90 days, single-engine and directly queryable. |

---

## Decisions & caveats (important)

These are the judgment calls that pure similarity/keyword search over the workspace would miss:

1. **`invoice_revenue` is GROSS, not NET.** The view filters to `invoice_status = 'POSTED'` and
   **does not touch refunds**. Reusing it alone would silently mislabel gross revenue as net.
   This implementation reuses it for the gross component and **nets out approved refunds** to meet
   the "net recognized revenue" requirement. If the registry exposes a certified
   net-recognized-revenue metric, prefer that over this composition.

2. **Active customer = enterprise commercial activity, not marketing logins.** The request asks for
   the definition used by executive dashboards. I did **not** reuse
   `marketing.logic.active_customer` because:
   - It encodes a **marketing-portal-login** rule (`application_name = 'Marketing Portal'`), i.e. a
     marketing-specific definition, not an enterprise commercial-activity one.
   - It runs on **Databricks (PySpark)** while this metric runs on **Snowflake** — composing them
     forces a cross-warehouse export.
   - It depends on a `customer_logins` dataset that **is not present** in this workspace, so it
     cannot be executed here.
   Instead, active customers are derived from POSTED invoice activity in the trailing 90 days —
   a commercial-activity definition that is single-engine, queryable now, and closer to the
   enterprise notion of an active customer. **Confirm against the governed enterprise
   active-customer definition before certifying for executive reporting.**

3. **Window is a single source of truth.** The trailing-90-day window (`params` CTE, anchored on
   `CURRENT_DATE()`) is applied identically to revenue, refunds, and activity. Change the anchor in
   one place to re-run for a historical date.

4. **FX availability.** Both `invoice_revenue` and `normalize_currency` require a matching row in
   `dim_exchange_rates` for the transaction date; rows without a rate are dropped by their inner
   joins. This matches existing platform behavior but can under-count revenue/refunds on dates
   missing FX data.

---

## How to run

```sql
-- create/refresh the view, then:
SELECT * FROM finance.arpac_90d;
```

Returns one row: `window_start_date`, `as_of_date`, `gross_revenue_usd`, `refunds_usd`,
`net_recognized_revenue_usd`, `active_customer_count`, `arpac_90d_usd`.
