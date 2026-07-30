# Scenario workspaces (what Copilot *sees* in each pattern)

These three directories make the walkthrough's three patterns concrete. Each `scenario-*`
folder is a **self-contained illustration of the workspace an analytics engineer + Copilot are
given** for the same task:

> "Create a trailing-90-day **ARPAC** (Average Revenue per Active Customer) for executive
> reporting. ARPAC = net recognized revenue in USD ÷ number of active customers. Reuse existing
> definitions, datasets or logic where appropriate."

They are **demonstration inputs**, not wired into the registry engine. The governed artifacts the
engine actually indexes live in [`../registry/manifests/`](../registry/manifests/);
the executable engine, CLI and MCP server live in [`../registry/`](../registry/). The narrated
run with real command output is [`../demo/walkthrough.md`](../demo/walkthrough.md).

| Scenario | What the workspace exposes | What Copilot does | Failure / success |
|---|---|---|---|
| [`scenario-1a`](scenario-1a/) | Base warehouse tables only — Snowflake (`dim_customers`, `fact_invoices`, `fact_refunds`) | Authors ARPAC from first principles | Re-implements revenue recognition; ignores currency; uses the wrong (12-month) active flag |
| [`scenario-1b`](scenario-1b/) | Base tables (Snowflake) **+** finance (Snowflake) & marketing (Databricks) domain repos | Reuses the most *similar* artifacts it finds | Reuses a **retired** invoice-revenue view (skips refunds) and a **marketing** active-customer rule (logins) on a **different engine** — similarity ≠ authority |
| [`scenario-2`](scenario-2/) | The **DRY Artifact Registry** (via CLI / MCP agent) | Searches by intent, checks lifecycle & ownership, resolves bindings, composes | Reuses the certified revenue + active-customer definitions; authors only the ratio |

## SQL dialect convention (Task 8)

The scenarios simulate **heterogeneous warehouse technologies**, because cross-engine duplication is
exactly the problem the registry exists to govern:

| Repository / domain | Engine & dialect |
|---|---|
| `shared` DWH | Snowflake |
| `finance-domain` | Snowflake |
| `marketing-domain` | Databricks (PySpark + Spark SQL) |
| `enterprise-analytics` (the ARPAC author) | Snowflake |

Two rules keep this realistic without becoming noise:

1. **Existing source artifacts are written in their home engine's dialect** — finance marts in
   Snowflake, marketing logic in PySpark. Each file is single-dialect and internally consistent
   (never four dialects mixed in one query).
2. **Authored ARPAC uses the consumer's single dialect.** Enterprise-analytics runs Snowflake, so
   the generated ARPAC is Snowflake SQL calling the resolved Snowflake bindings directly — that is
   what makes it *executable*. Reuse is still surface-neutral: the certified `recognize_revenue` is
   one identity with two bindings on the Snowflake stack — the native UDF and a dbt macro
   (`dry_finance_macros.recognize_revenue`) — so a dbt author resolves the macro and a raw-SQL author
   resolves the UDF, both the *same* governed definition. Cross-*engine* reuse lives at the platform
   level, where the marketing active-customer rule runs on Databricks. Portability is demonstrated by
   the **binding set in the registry**, not by writing un-executable ANSI.

## The intended contrasts

| Concept | Scenario 1A picks | Scenario 1B picks | Scenario 2 picks (authoritative) |
|---|---|---|---|
| Revenue | raw `fact_invoices` sums (no recognition, no refunds, no FX) | `finance.invoice_revenue` (retired view; skips refunds) | `finance.logic.recognize_revenue.v1` (certified, Snowflake) |
| Active customer | `dim_customers.is_active` (12-month order flag) | `marketing.logic.active_customer` (portal logins) | `sales.datasets.commercial_customer_status_90d.v1` (certified 90-day commercial activity, Databricks) |

Only the registry (scenario 2) knows the **lifecycle** (certified / shared / retired) and
**ownership** that separate an authoritative definition from a plausible-looking copy.
