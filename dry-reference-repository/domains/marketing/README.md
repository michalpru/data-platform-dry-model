# Marketing domain (example)

This domain illustrates **cross-domain reuse** — specifically, how the marketing team:

1. Reuses the **enterprise Customer entity** (`enterprise.semantics.customer.v1`) as the base semantic model
2. Reuses **platform packages** (`dry_platform_utils`, `dry_shared_macros`) via dependency management
3. Defines a **domain-local metric** (`active_customers_30d`) for campaign targeting, clearly labeled as NOT for cross-domain comparison
4. Uses the **certified enterprise metric** (`enterprise.metrics.active_customer.v1`) for any executive-facing reporting

## The "Active Customer" problem, illustrated

| Context | Definition | Lifecycle |
|---|---|---|
| Executive dashboard | `enterprise.metrics.active_customer.v1` (90-day window) | `certified` — use this |
| Marketing campaign targeting | `marketing.metrics.active_customers_30d.v1` (30-day window) | `local` — domain only |

Before the platform introduced `enterprise.metrics.active_customer.v1`, the marketing team had their 30-day definition embedded in SQL views. Finance had their own variant. The two diverged silently.

## Folder structure

- `datasets/` — transformation models producing queryable datasets
- `contracts/datasets/` — dataset interface contracts (schema + grain + SLOs)
- `semantics/models/` — domain semantic model (extends enterprise customer entity)
- `semantics/metrics/` — domain-local metrics (campaign targeting, NOT for cross-team comparison)
- `dependencies/` — platform package dependencies (reuse declared, not copied)
