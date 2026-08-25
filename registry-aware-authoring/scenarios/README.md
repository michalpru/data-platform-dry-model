# Scenario workspaces (what Copilot *sees* in each scenario)

Each `scenario-*` folder is a self-contained illustration of the workspace an analytics engineer +
Copilot are given for the same task: build a trailing-90-day **ARPAC** (Average Revenue per Active
Customer) for executive reporting, reusing governed definitions instead of rebuilding them.

These are **demonstration inputs**, not wired into the registry engine. The governed artifacts the
engine indexes are the pure-YAML manifests in
[`scenario-2/registry-manifests/`](scenario-2/registry-manifests/); the code their bindings point at
lives in [`scenario-2/workspace/`](scenario-2/workspace/); the executable engine, CLI and MCP server
live in [`../registry/`](../registry/).

| Scenario | Workspace exposed | Outcome |
|---|---|---|
| [**1A** — base tables](scenario-1a/) | Base warehouse tables only (Snowflake) | Authors ARPAC from first principles — re-derives revenue, ignores currency, wrong active flag |
| [**1B** — base + domain repos](scenario-1b/) | Base tables **+** Finance (Snowflake) & Marketing (Databricks) repos | Reuses a **retired** view and a **marketing** login rule — similarity ≠ authority |
| [**1C** — all existing codebase](scenario-1c/) | The *entire* codebase, incl. the certified logic exposed as source | Reuses the certified numerator, but still picks the Sales look-alike denominator |
| [**2** — registry-aware](scenario-2/) | The **DRY Artifact Registry** (CLI / MCP agent) | Resolves the certified definitions + bindings; authors only the ratio |

## The intended contrasts

| Concept | 1A picks | 1B picks | 1C picks | 2 picks (authoritative) |
|---|---|---|---|---|
| Revenue | raw `fact_invoices` sums | `finance.invoice_revenue` (retired) | `recognize_revenue` (certified) | `finance.logic.recognize_revenue.v1` (certified) |
| Active customer | `dim_customers.is_active` (12-mo flag) | `marketing…active_customer` (logins) | `sales…active_customer_90d` (look-alike) | `sales.datasets.commercial_customer_status_90d.v1` (certified) |

Only the registry (Scenario 2) carries the **lifecycle** (certified / shared / retired) and
**ownership** that separate an authoritative definition from a plausible-looking copy. The scenarios
also span **heterogeneous engines** (Snowflake for the shared DWH, Finance and the enterprise author;
Databricks for Sales and Marketing) — cross-engine duplication is exactly what the registry governs.

- **Narrated run with real command output & VS Code screenshots:** [`../demo-walkthrough.md`](../demo-walkthrough.md)
- **Recorded results & scoring (single source):** [`../poc-results.md`](../poc-results.md)
