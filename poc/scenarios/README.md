# Scenario workspaces (what Copilot *sees* in each pattern)

These three directories make the walkthrough's three patterns concrete. Each `scenario-*`
folder is a **self-contained illustration of the workspace an analytics engineer + Copilot are
given** for the same task:

> "Create a trailing-90-day **ARPAC** (Average Revenue per Active Customer) for executive
> reporting. ARPAC = net recognized revenue in USD ÷ number of active customers. Reuse existing
> definitions, datasets or logic where appropriate."

They are **demonstration inputs**, not wired into the registry engine. The governed artifacts the
engine actually indexes live in [`../../dry-reference-repository/`](../../dry-reference-repository/);
the executable engine, CLI and MCP server live in [`../registry/`](../registry/). The narrated
run with real command output is [`../demo/walkthrough.md`](../demo/walkthrough.md).

| Scenario | What the workspace exposes | What Copilot does | Failure / success |
|---|---|---|---|
| [`scenario-1a`](scenario-1a/) | Base warehouse tables only (`dim_customers`, `fact_invoices`, `fact_refunds`) | Authors ARPAC from first principles | Re-implements revenue recognition; ignores currency; uses the wrong (12-month) active flag |
| [`scenario-1b`](scenario-1b/) | Base tables **+** finance & marketing domain repos | Reuses the most *similar* artifacts it finds | Reuses a **retired** invoice-revenue view (skips refunds) and a **marketing** active-customer rule (logins) — similarity ≠ authority |
| [`scenario-2`](scenario-2/) | The **DRY Artifact Registry** (via CLI / MCP agent) | Searches by intent, checks lifecycle & ownership, resolves bindings, composes | Reuses the certified revenue + active-customer definitions; authors only the ratio |

## SQL dialect convention (Task 8)

All authored example SQL in these scenarios is **portable ANSI SQL**. Dialect-specific objects
(Databricks SQL, Snowflake SQL, Spark) are *not* shown inline — they exist only as
**implementation bindings** inside the registry. `resolve_binding` maps the ANSI composition to
the correct physical object for the engineer's runtime. This demonstrates portability without
drowning the reader in four SQL dialects.

## The intended contrasts

| Concept | Scenario 1A picks | Scenario 1B picks | Scenario 2 picks (authoritative) |
|---|---|---|---|
| Revenue | raw `fact_invoices` sums (no recognition, no refunds, no FX) | `finance.invoice_revenue` (retired view; skips refunds) | `finance.metrics.net_recognized_revenue.v1` → `finance.logic.recognize_revenue.v1` (certified) |
| Active customer | `dim_customers.is_active` (12-month order flag) | `marketing.logic.active_customer` (portal logins) | `enterprise.metrics.active_customer.v1` (enterprise 90-day commercial activity) |

Only the registry (scenario 2) knows the **lifecycle** (certified / shared / retired) and
**ownership** that separate an authoritative definition from a plausible-looking copy.
