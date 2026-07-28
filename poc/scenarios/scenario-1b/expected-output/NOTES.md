# Scenario 1B — expected outcome

**What Copilot produces:** [`arpac_90d.sql`](arpac_90d.sql) — it *reuses* existing artifacts, which
feels like the right thing to do. But it reuses the wrong ones.

| Concern | 1B reuses | Problem | Authoritative (registry) |
|---|---|---|---|
| Revenue | `finance.invoice_revenue` | **Retired** view; skips refunds; invoice-date based | `finance.metrics.net_recognized_revenue.v1` → `recognize_revenue.v1` (certified) |
| Active customer | `marketing.logic.active_customer` | **Marketing** login rule, not enterprise | `enterprise.metrics.active_customer.v1` (certified, 90-day commercial activity) |

**Why workspace search cannot save this scenario:**

1. **No authority signal.** The ranking is by resemblance. Nothing in the workspace states that
   `invoice_revenue` is *retired* or that the marketing rule is *not enterprise-approved*.
2. **Workspace-bounded.** The certified `recognize_revenue` binding (a warehouse UDF) and the
   enterprise active-customer contract may live in repos not checked out here — invisible to the scan.
3. **Similarity ≠ semantics.** The revenue-vs-net-revenue and marketing-vs-enterprise divergences
   barely register structurally, yet they are the consequential errors.

**Detection available in this scenario:** workspace similarity search (Pattern 2) — informative,
low/medium confidence, **no governance**. It can say "this looks like existing code"; it cannot say
"that existing code is retired / not authoritative."

**Takeaway:** reuse without governance can be *worse* than authoring from scratch, because it lends
false confidence. Scenario 2 adds the lifecycle + ownership signal that makes reuse safe.
