# Scenario 1B — Standard Copilot authoring, warehouse **+** domain repos

**Workspace exposed to Copilot:** the base warehouse tables *and* two domain repositories.
**Engines:** the shared DWH and the finance-domain run on **Snowflake**; the marketing-domain runs
on **Databricks (PySpark + Spark SQL)** — so reusing the marketing rule means crossing warehouses.

```
workspace/
├── dwh/
│   └── shared/
│       └── datasets/
│           ├── dim_customers.sql
│           ├── fact_invoices.sql
│           └── fact_refunds.sql
├── finance-domain/
│   └── finance/
│       ├── datasets/
│       │   ├── dim_exchange_rates.sql
│       │   └── invoice_revenue.sql      ← LEGACY / RETIRED view (skips refunds)
│       └── logic/
│           └── normalize_currency.sql   ← shared currency utility
└── marketing-domain/
    └── marketing/
        └── logic/
            └── active_customer.py       ← Databricks PySpark rule (portal logins, NOT enterprise)
```

**What happens.** Copilot can now discover reusable implementations across the workspace and, quite
reasonably, reuses the ones that look most similar to the request:

- **Revenue** → `finance.invoice_revenue`. It is a real, working view that normalizes currency —
  but it is the **retired** legacy approach: it computes revenue from `POSTED` invoices only and
  **skips refunds and credit notes**, and it has no recognition-timing rules. It was superseded by
  the certified `recognize_revenue` logic, yet it is still in the repo.
- **Active customer** → `marketing.logic.active_customer`. A Python function encoding a
  **marketing-specific** rule (a customer is active if they logged into the Marketing Portal in the
  window). This is not the enterprise commercial-activity definition.

Both artifacts are discoverable and look reusable. **Similarity and availability are not business
authority** — this is the core Scenario 1B failure the whitepaper names. Workspace search can rank by
resemblance, but it cannot tell you that `invoice_revenue` is *retired* or that the marketing rule
is *not enterprise-approved*. Only the registry (scenario 2) carries lifecycle and ownership.

Worse, the two picks live on **different engines**: the revenue view is Snowflake, the
active-customer rule is a Databricks PySpark job. Composing them forces the engineer to export the
Databricks output and land it in Snowflake — a brittle cross-warehouse hop that similarity search
never surfaces.

See [`expected-output/arpac_90d.sql`](expected-output/arpac_90d.sql) and
[`expected-output/NOTES.md`](expected-output/NOTES.md).
