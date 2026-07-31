# Registered artifacts index (reference)

In a real DRY Artifact Registry, this is queryable (API/UI).  
In this reference repo, the YAML set in this folder is the snapshot.

> **Note — this reference index is separate from the executable PoC.** The executable PoC keeps its
> own **self-contained** input registry as pure-YAML manifests under
> `poc/scenarios/scenario-2/registry-manifests/` (shared base tables + finance/sales logical &
> dataset artifacts), with the code its bindings point at under
> `poc/scenarios/scenario-2/workspace/`. The PoC does **not** load from this folder. The shared
> platform packages used by the reference repo live in `dry-reference-repository/platform/packages/`.
> The artifacts listed below are **generic reference examples** (a different naming universe from the
> PoC's `fact_billable_events` / `recognize_revenue` / `commercial_customer_status_90d` set); they
> illustrate registry structure and are retained for reference context only.

**Population model:** CI/CD parses artifact manifests on merge and publishes here.  
Domain teams declare artifacts in their own repos; certification gates control what reaches this index.

## Organizational scope rule

Only **shared or certified artifacts** are registered here.  
- Domain-local artifacts (`lifecycle: local`) stay in their domain repo, not here.  
- A domain team can own a registered artifact (e.g., Finance owns `finance.reporting.*`).  
- Enterprise artifacts are owned by the Data Governance function and apply cross-domain.

## How to find an artifact

Search by FQN (exact):
- `finance.reporting.revenue_events.v1`
- `enterprise.reporting.customer.v1`

Search by domain namespace prefix:
- `finance.reporting.*`
- `enterprise.*`

Search by concept keyword (advisory — imprecise):
- `revenue`, `arpac`, `recognize_revenue`, `netting`, `currency`, `active_customer`, `customer`

## Current registered artifacts

| FQN | Interface type | Owner | Lifecycle |
|---|---|---|---|
| `platform.callable.dry_platform_utils.v1` | callable_logic | data-platform | shared |
| `platform.callable.dry_shared_macros.v1` | callable_logic | data-platform | shared |
| `finance.logic.recognize_revenue.v1` | callable_logic | finance-analytics | certified |
| `finance.logic.normalize_reporting_currency.v1` | callable_logic | finance-analytics | shared |
| `finance.reporting.revenue_events.v1` | queryable_dataset | finance-analytics | certified |
| `finance.reporting.invoice_revenue.v1` | queryable_dataset | finance-analytics | **retired** |
| `finance.metrics.net_recognized_revenue.v1` | semantic_contract | finance-analytics | certified |
| `finance.metrics.arpac.v1` | semantic_contract | revenue-analytics | shared |
| `enterprise.reporting.customer.v1` | queryable_dataset, semantic_contract | data-governance | certified |
| `enterprise.semantics.customer.v1` | semantic_contract | data-governance | certified |
| `enterprise.metrics.active_customer.v1` | semantic_contract | data-governance | certified |

**Implementation Bindings note:** `finance.logic.recognize_revenue.v1` is one logical identity
with two bindings on the Snowflake stack — a native warehouse SQL UDF
(`analytics.finance.fn_recognize_revenue`) and a dbt macro (`dry_finance_macros.recognize_revenue`)
that calls it. Reuse through either surface is recorded as one governed definition, not as
duplication: dbt solves reuse *inside* dbt, and the registry records that the macro and the UDF
are the same certified capability.

**Retired artifacts note:** `finance.reporting.invoice_revenue.v1` is registered with
`lifecycle: retired` on purpose. It is a legacy revenue view (skips refunds, no recognition
rules) that was superseded by the certified recognized-revenue path. Workspace similarity search
(scenario 1B) surfaces it as "reusable" with no lifecycle signal; only the registry records that
it must not be reused. This is the registry demonstrating **rejection of a retired artifact**.

**Not registered (domain-local artifacts — intentionally excluded):**

| FQN | Reason | Points to certified |
|---|---|---|
| `marketing.reporting.active_customers_30d.v1` | `lifecycle: local` — 30-day campaign window, not for cross-domain comparison | `enterprise.metrics.active_customer.v1` |
| `marketing.metrics.active_customers_30d.v1` | `lifecycle: local` — domain-internal metric | `enterprise.metrics.active_customer.v1` |
