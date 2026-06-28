# Registered artifacts index (reference)

In a real DRY Artifact Registry, this is queryable (API/UI).  
In this reference repo, the YAML set in this folder is the snapshot.

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
- `revenue`, `active_customer`, `customer`

## Current registered artifacts

| FQN | Interface type | Owner | Lifecycle |
|---|---|---|---|
| `platform.callable.dry_platform_utils.v1` | callable_logic | data-platform | shared |
| `platform.callable.dry_shared_macros.v1` | callable_logic | data-platform | shared |
| `finance.reporting.revenue_events.v1` | queryable_dataset | finance-analytics | certified |
| `finance.metrics.net_recognized_revenue.v1` | semantic_contract | finance-analytics | certified |
| `enterprise.reporting.customer.v1` | queryable_dataset, semantic_contract | data-governance | certified |
| `enterprise.semantics.customer.v1` | semantic_contract | data-governance | certified |
| `enterprise.metrics.active_customer.v1` | semantic_contract | data-governance | certified |

**Not registered (domain-local artifacts — intentionally excluded):**

| FQN | Reason | Points to certified |
|---|---|---|
| `marketing.reporting.active_customers_30d.v1` | `lifecycle: local` — 30-day campaign window, not for cross-domain comparison | `enterprise.metrics.active_customer.v1` |
| `marketing.metrics.active_customers_30d.v1` | `lifecycle: local` — domain-internal metric | `enterprise.metrics.active_customer.v1` |
