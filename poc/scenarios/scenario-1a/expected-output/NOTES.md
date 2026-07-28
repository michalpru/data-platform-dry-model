# Scenario 1A — expected outcome

**What Copilot produces:** [`arpac_90d.sql`](arpac_90d.sql) — a single ANSI SQL query that runs
and looks correct.

**Why it is wrong (three silent governance defects):**

| Concern | What the 1A output does | Authoritative definition (registry) |
|---|---|---|
| Revenue recognition | Sums raw `POSTED` invoice amounts | `finance.logic.recognize_revenue.v1` applies recognition rules |
| Refunds / credit notes | Ignored (`fact_refunds` never joined) | Netted inside `recognize_revenue` → `net_recognized_revenue.v1` |
| Currency | Ignored (no FX table in workspace) | Normalized to USD by `normalize_reporting_currency.v1` |
| Active customer | `dim_customers.is_active` (12-month order flag) | `enterprise.metrics.active_customer.v1` (90-day commercial activity) |

**Detection available in this scenario:** none. This is the whitepaper's *"AI assistant as
duplication amplifier"* — the divergent metric reaches review or production as new "original" code.

**Takeaway:** without discoverable enterprise definitions, similarity/search cannot help because
there is nothing authoritative to find. Scenario 1B adds domain repos; scenario 2 adds the registry.
