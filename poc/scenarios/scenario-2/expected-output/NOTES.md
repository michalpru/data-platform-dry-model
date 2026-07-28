# Scenario 2 — expected outcome

**What Copilot produces:** [`arpac_90d.sql`](arpac_90d.sql) — a small **Snowflake SQL** ratio that
composes two **certified** definitions resolved from the registry. No revenue-recognition rule, no
netting rule, no currency rule and no activity window is re-implemented.

**Why this scenario succeeds where 1A/1B failed:**

| Signal | 1A | 1B | 2 (registry) |
|---|---|---|---|
| Finds similar code | ✗ | ✓ (workspace) | ✓ (whole platform) |
| Knows which is **certified / canonical** | ✗ | ✗ | ✓ |
| Sees warehouse-only / other-repo artifacts | ✗ | ✗ | ✓ |
| Rejects **retired** / non-enterprise variants | ✗ | ✗ | ✓ |
| Resolves the right **binding** for the runtime | ✗ | ✗ | ✓ |

**The decisive difference is authority.** The registry states that `net_recognized_revenue` and
`active_customer` are *certified* and *owned*, that `invoice_revenue` is *retired*, and that the
marketing active-customer rule is *not enterprise*. Similarity search (1B) cannot know any of that.

**Detection available in this scenario:** registry-backed canonical resolution (Pattern 3) —
high confidence, prevention at authoring time, plus optional `compare_code` verification.

**Net effect on ARPAC:** a single governed number, comparable across every executive dashboard,
built by composition rather than re-derivation — the whitepaper's *"AI assistant as reuse
accelerator."*
