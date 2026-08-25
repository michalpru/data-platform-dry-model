# Scenario 1A — Workspace-only (base tables)

**Workspace exposed to Copilot:** the central data-warehouse base tables only.
**Engine:** the shared DWH runs on **Snowflake** — all SQL in this scenario is Snowflake dialect.

```
workspace/
└── dwh/
    └── shared/
        └── datasets/
            ├── dim_customers.sql     ← has is_active (12-month order flag — NOT enterprise-grade)
            ├── fact_invoices.sql
            └── fact_refunds.sql
```

With no governed definitions visible, every model authors ARPAC from first principles — silently
re-deriving revenue recognition, skipping currency normalization, and misusing `dim_customers.is_active`
(a 12-month order flag) as the active-customer definition. The *duplication amplifier* baseline.

- **Setup & narrated run:** [`../../demo-walkthrough.md`](../../demo-walkthrough.md) (Scenario 1A)
- **Recorded results & scoring:** [`../../poc-results.md`](../../poc-results.md)
- **Raw model outputs:** [`poc-results/`](poc-results/)
