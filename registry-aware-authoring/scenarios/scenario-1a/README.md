# Scenario 1A — Standard Copilot authoring, warehouse tables only

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

**What happens.** Copilot has no enterprise business definitions for *recognized revenue* or
*active customer*. It authors ARPAC "from first principles" using the visible warehouse assets and
makes three governance mistakes:

1. **Revenue** = raw `POSTED` invoice amounts — no revenue-recognition rules, and refunds/credit
   notes (`fact_refunds`) are never netted.
2. **Currency** is ignored — there is no exchange-rate table in this workspace, so mixed-currency
   `invoice_amount` values are summed as if all USD.
3. **Active customer** = `dim_customers.is_active`, a *12-month order* flag, **not** the certified
   90-day commercial-activity definition used by other executive dashboards.

The result runs and looks plausible, but the number is **not comparable** to governed ARPAC.
Nothing in this workspace can detect the divergence.

See [`expected-output/arpac_90d.sql`](expected-output/arpac_90d.sql) and
[`expected-output/NOTES.md`](expected-output/NOTES.md).
