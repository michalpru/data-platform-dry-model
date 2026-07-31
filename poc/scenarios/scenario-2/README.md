# Scenario 2 — Registry-aware Copilot authoring

**Workspace exposed to Copilot:** the **DRY Artifact Registry**, reached through the thin MCP server and the **DRY Reuse** custom agent (or the CLI). Unlike scenarios 1A/1B, authoring starts with **resolution**, not generation.

The governed artifacts this scenario resolves against are the **pure-YAML** manifests in
[`registry-manifests/`](registry-manifests/) (`shared/` base tables plus `domains/finance/` and
`domains/sales/`). The registry holds no code; each binding's `source` points into
[`workspace/`](workspace/), the mocked repositories where the real implementations live. The
`workspace/enterprise/` tree is the **empty authoring target** the agent writes into.

## The registry-aware workflow (intent-first)

1. **Search the whole intent first.** `search_artifacts("ARPAC", interface_type="semantic_contract")`.
   If a certified ARPAC already existed, reuse it and stop.
2. **No single match? Recommend a composition.**
   `recommend_composition("ARPAC", ["recognize revenue", "commercial customer status"])` resolves each named component to a registered artifact **and** its binding, and flags anything missing.
3. **Check lifecycle & ownership.** The registry returns authority the workspace never had:

   | Component | Resolved artifact | Lifecycle | Owner | Engine |
   |---|---|---|---|---|
   | Recognize revenue | `finance.logic.recognize_revenue.v1` | certified | finance-analytics | Snowflake |
   | Commercial customer status | `sales.datasets.commercial_customer_status_90d.v1` | certified | sales-analytics | **Databricks** |

   Contrast with the workspace pick-ups from scenario 1B that the registry keeps out of the
   result: the legacy `finance.datasets.invoice_revenue.v1` is registered but carries
   `lifecycle: retired` (superseded), so it is **discoverable-and-rejected**; the marketing
   active-customer rule is **domain-local and never registered**, so registry-aware authoring
   never surfaces it at all. Either way the engineer lands on the certified definition.
4. **Resolve bindings — across engines.** `resolve_binding(...)` returns the physical object for each component's runtime/dialect. Revenue resolves to a **Snowflake** UDF; the active-customer status resolves to a **Databricks** view. Enterprise-analytics runs on Snowflake, so the Databricks status is surfaced into Snowflake via Delta Sharing and the cross-engine join is materialized once in the governed components dataset.
5. **Author only what is missing** — the components dataset `enterprise.datasets.customer_arpac_components_90d` and the ARPAC ratio `enterprise.semantic.arpac_90d` on top of it.
6. **(Optional) verify.** `compare_code` the generated SQL against the registry to confirm it does not re-implement governed logic.

## SQL dialect (Task 8)

The enterprise-analytics domain runs on **Snowflake**, so both authored artifacts in
[`expected-output/`](expected-output/) are **Snowflake SQL**. The catch is that only *one* of the
two governed inputs is native to Snowflake: `recognize_revenue` resolves to a Snowflake UDF, but
`commercial_customer_status_90d` resolves to a **Databricks** view. Authoring in the consumer's
single dialect stays executable because the components dataset
[`expected-output/customer_arpac_components_90d.sql`](expected-output/customer_arpac_components_90d.sql)
brings the Databricks status into Snowflake via Delta Sharing — the cross-engine hop the registry
records and `resolve_binding` makes explicit.

Portability is not lost; it moves into the registry. `recognize_revenue` is one certified identity
with two bindings on the Snowflake stack — the native UDF and a **dbt macro**
(`dry_finance_macros.recognized_revenue_relation`). A dbt model reuses it with `{{ recognized_revenue_relation(...) }}`;
a raw-SQL author calls the UDF; both are the *same* governed definition. `resolve_binding … --runtime dbt`
returns the macro, `--runtime warehouse` the UDF. dbt solves reuse *inside* dbt on one engine; the
registry records that the macro and the UDF are one capability — and spans the Databricks stack that
dbt on Snowflake never sees (the Sales active-customer view lives on Databricks).

See [`expected-output/NOTES.md`](expected-output/NOTES.md). The full narrated run with real command output is [`../../demo/walkthrough.md`](../../demo/walkthrough.md) (Pattern 3).
