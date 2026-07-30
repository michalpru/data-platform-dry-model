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
> Resolved **Snowflake** binding: `analytics.finance.fn_recognize_revenue`.
> Reused `sales.datasets.commercial_customer_status_90d` because it is Sales-owned and certified.
> Resolved **Databricks** binding: `sales.datasets.commercial_customer_status_90d`.
> Created only the missing Enterprise Analytics composition:
> `enterprise.datasets.customer_arpac_components_90d` and `enterprise.semantic.arpac_90d`.

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
revenue input and the Databricks view for the status input; the cross-engine join is materialized
once, in the governed components dataset.

**Detection available in this scenario:** registry-backed canonical resolution (Pattern 3) —
high confidence, prevention at authoring time, plus optional `compare_code` verification.

**Net effect on ARPAC:** a single governed number, comparable across every executive dashboard,
built by composition across engines rather than re-derivation — the whitepaper's *"AI assistant as
reuse accelerator."*
