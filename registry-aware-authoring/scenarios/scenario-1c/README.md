# Scenario 1C — Workspace-only (all existing codebase)

**Workspace exposed to Copilot:** the *entire* codebase — every domain repository checked out and
every warehouse object exposed as source, including the certified `recognize_revenue` logic and the
certified `commercial_customer_status_90d` view. The most optimistic workspace-only assumption.

```
workspace/
├── dwh/shared/datasets/         ← dim_customers, fact_invoices, fact_refunds
├── finance-domain/finance/      ← dim_exchange_rates, fact_billable_events, invoice_revenue (RETIRED),
│                                   normalize_currency, recognize_revenue (CERTIFIED)
├── sales/datasets/              ← commercial_customer_status_90d (CERTIFIED denominator),
│                                   active_customer_90d (look-alike — POSTED invoice only)
└── marketing-domain/marketing/  ← active_customer.py (portal-login rule)
```

With the whole codebase visible, every model reuses the certified `recognize_revenue` for the
numerator, but still picks the Sales `active_customer_90d` look-alike over the certified denominator
— the certified view's Sales dependencies are not materialized (so it "does not run") while the
look-alike reads the always-present shared tables. Reachable but not distinguishable: code access
alone supplies no authority signal.

- **Setup & narrated run:** [`../../demo-walkthrough.md`](../../demo-walkthrough.md) (Scenario 1C)
- **Recorded results & scoring:** [`../../poc-results.md`](../../poc-results.md)
- **Raw model outputs:** [`poc-results/`](poc-results/)
