# Scenario 2 — expected outcome

**What Copilot produces:** exactly two small, governed artifacts — the only parts that were
actually missing:

1. [`customer_arpac_components_90d.sql`](customer_arpac_components_90d.sql) —
   `enterprise.datasets.customer_arpac_components_90d.v1`, the per-customer components dataset that
   joins the two certified inputs.
2. [`arpac_90d.sql`](arpac_90d.sql) + [`arpac_90d.metric.yaml`](arpac_90d.metric.yaml) —
   `enterprise.semantic.arpac_90d.v1`, the ARPAC ratio and its semantic contract, built **on top of**
   that dataset.

No revenue-recognition rule, no netting rule, no currency rule and no activity window is
re-implemented. Each is a resolved, certified binding.

**The agent's reasoning, stated plainly:**

> Reused `finance.logic.recognize_revenue` because it is Finance-owned and certified.
> Resolved **Snowflake** binding: `FINANCE.LOGIC.RECOGNIZE_REVENUE`.
> Reused `sales.datasets.commercial_customer_status_90d` because it is Sales-owned and certified.
> Resolved **Databricks** binding: `sales.datasets.commercial_customer_status_90d`.
> There is **no Snowflake binding** for the Sales status view — I referenced the resolved
> Databricks binding under an explicit "reachable from Snowflake once a binding is provisioned"
> precondition and flagged provisioning it as an integration requirement. I did **not** fabricate a
> bridge object.
> Created only the missing Enterprise Analytics composition:
> `enterprise.datasets.customer_arpac_components_90d` and `enterprise.semantic.arpac_90d`.

**Populations (certified definition):** the denominator is the distinct count of customers with
`is_active_commercial_90d = true` on the reporting date; the numerator is net recognized revenue in
USD over the trailing 90 days, counting **only** revenue from those active customers. The reporting
date is a parameter (`:as_of_date`), not `CURRENT_DATE()`, so point-in-time snapshots are reproducible.

**Why this scenario succeeds where 1A/1B failed:**

| Signal | 1A | 1B | 2 (registry) |
|---|---|---|---|
| Finds similar code | ✗ | ✓ (workspace) | ✓ (whole platform) |
| Knows which is **certified / canonical** | ✗ | ✗ | ✓ |
| Sees artifacts on **other engines** (Databricks) | ✗ | ✗ | ✓ |
| Rejects **retired** / non-enterprise variants | ✗ | ✗ | ✓ |
| Resolves the right **binding** for each runtime | ✗ | ✗ | ✓ |

**The decisive difference is authority — and reach across engines.** The registry states that
`recognize_revenue` and `commercial_customer_status_90d` are *certified* and *owned*, that the
legacy `invoice_revenue` is *retired*, and — crucially — that the active-customer input lives on
**Databricks** while revenue lives on **Snowflake**. Similarity search (1B) can see neither the
authority nor the artifact on the other engine. `resolve_binding` returns the Snowflake UDF for the
revenue input and the Databricks view for the status input — and, just as importantly, returns **no**
Snowflake binding for the status view. The registry *surfaces* that cross-engine gap rather than
hiding it; the components dataset references the resolved Databricks binding under an explicit
reachability precondition and flags provisioning a Snowflake binding as an integration requirement.
No bridge object is fabricated.

**Detection available in this scenario:** registry-backed canonical resolution (Scenario 2) —
high confidence, prevention at authoring time, plus optional `compare_code` verification.

**Net effect on ARPAC:** a single governed number, comparable across every executive dashboard,
built by composition across engines rather than re-derivation — the whitepaper's *"AI assistant as
reuse accelerator."*
