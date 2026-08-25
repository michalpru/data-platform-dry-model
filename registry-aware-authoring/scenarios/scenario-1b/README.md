# Scenario 1B — Workspace-only (base tables + domain repositories)

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

More context, less safety: models reuse the most *similar* code they find — the **retired**
`invoice_revenue` view (skips refunds) and the Marketing portal-login rule — on two different engines
(Snowflake + Databricks). Similarity and availability are not authority, and the certified
definitions are invisible to workspace search.

- **Setup & narrated run:** [`../../demo-walkthrough.md`](../../demo-walkthrough.md) (Scenario 1B)
- **Recorded results & scoring:** [`../../poc-results.md`](../../poc-results.md)
- **Raw model outputs:** [`poc-results/`](poc-results/)
