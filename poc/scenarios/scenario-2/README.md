# Scenario 2 — Registry-aware Copilot authoring

**Workspace exposed to Copilot:** the **DRY Artifact Registry**, reached through the thin MCP
server and the **DRY Reuse** custom agent (or the CLI). Unlike scenarios 1A/1B, authoring starts
with **resolution**, not generation.

The governed artifacts this scenario resolves against already live in the mocked registry at
[`../../../dry-reference-repository/`](../../../dry-reference-repository/) (registered manifests
under `platform/registry/registered/`). There is no separate `workspace/` folder here because the
"workspace" *is* the registry — that is the point of the scenario.

## The registry-aware workflow (intent-first)

1. **Search the whole intent first.** `search_artifacts("ARPAC", interface_type="semantic_contract")`.
   If a certified ARPAC already existed, reuse it and stop.
2. **No single match? Recommend a composition.**
   `recommend_composition("ARPAC", ["net recognized revenue", "active customer"])` resolves each
   named component to a registered artifact **and** its binding, and flags anything missing.
3. **Check lifecycle & ownership.** The registry returns authority the workspace never had:

   | Component | Resolved artifact | Lifecycle | Owner |
   |---|---|---|---|
   | Net recognized revenue | `finance.metrics.net_recognized_revenue.v1` (built on `finance.logic.recognize_revenue.v1`) | certified | finance-analytics |
   | Active customer | `enterprise.metrics.active_customer.v1` | certified | data-governance |

   Contrast with the workspace pick-ups from scenario 1B that the registry keeps out of the
   result: the legacy `finance.reporting.invoice_revenue.v1` is registered but carries
   `lifecycle: retired` (superseded), so it is **discoverable-and-rejected**; the marketing
   active-customer rule is **domain-local and never registered**, so registry-aware authoring
   never surfaces it at all. Either way the engineer lands on the certified definition.
4. **Resolve bindings.** `resolve_binding(...)` returns the physical object for the engineer's
   runtime/dialect. Enterprise-analytics runs **Snowflake**, so the authored ARPAC is Snowflake SQL
   that calls the resolved Snowflake bindings directly (native path — no cross-engine hop).
5. **Author only what is missing** — the ARPAC ratio itself.
6. **(Optional) verify.** `compare_code` the generated SQL against the registry to confirm it does
   not re-implement governed logic.

## SQL dialect (Task 8)

The enterprise-analytics domain runs on **Snowflake**, so the composition in
[`expected-output/arpac_90d.sql`](expected-output/arpac_90d.sql) is authored in **Snowflake SQL**
and calls the resolved Snowflake bindings directly. Authoring in the consumer's single dialect is
what makes the output *executable* — a pure-ANSI query cannot natively invoke a Snowflake
table-valued function.

Portability is not lost; it moves into the registry. `recognize_revenue` is one certified identity
with two bindings on the Snowflake stack — the native UDF and a **dbt macro**
(`dry_finance_macros.recognize_revenue`). A dbt model reuses it with `{{ recognize_revenue(...) }}`;
a raw-SQL author calls the UDF; both are the *same* governed definition. `resolve_binding … --runtime
dbt` returns the macro, `--runtime warehouse` the UDF. dbt solves reuse *inside* dbt; the registry
records that the macro and the UDF are one capability — and spans the engines dbt never sees (the
marketing active-customer rule lives on Databricks).

See [`expected-output/NOTES.md`](expected-output/NOTES.md). The full narrated run with real command
output is [`../../demo/walkthrough.md`](../../demo/walkthrough.md) (Pattern 3).
