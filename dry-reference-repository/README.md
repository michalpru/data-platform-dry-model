# DRY reference repository

This folder is a **tool-agnostic reference repository structure** showing how to organize repositories to support reuse across:
- callable logic
- queryable datasets
- semantic contracts

It demonstrates:
- separating platform-owned shared assets from domain-owned assets
- an enterprise tier for certified cross-domain semantic definitions
- declaring artifact identity (FQN), ownership, and lifecycle
- making "local vs shared vs certified" explicit and enforceable
- publishing shared and certified artifacts to a DRY Artifact Registry
- detecting duplication at build time and bypasses at runtime
- measuring structural reuse and behavioral adoption
- a second domain (marketing) showing how cross-domain reuse works in practice

## Monorepo vs multi-repo

This reference co-locates all layers in one folder for readability.
In practice, `platform/`, each `domains/*/`, and `enterprise/` typically live in **separate repositories**.

The DRY Artifact Registry is most valuable in multi-repo environments:
it provides cross-repo discovery and impact analysis that `grep` across local folders cannot.
CI gates trigger on PRs in any participating repo and publish to the shared registry.

## Structure overview

- `platform/` — organization-wide shareables (owned by a platform team / guild)
  - `packages/` — buildable, versioned distribution units (Python wheels, SQL macro packages)
  - `registry/` — DRY artifact registry (registered artifacts + observed runtime objects)
  - `ci/` — DRY promotion gates and duplication detection policy
  - `metrics/` — sample reuse scorecard definitions for structural and behavioral measurement

- `enterprise/` — certified cross-domain semantic definitions (owned by Data Governance)
  - `semantics/models/` — enterprise entity definitions (e.g., Customer entity, grain, standard dimensions)
  - `semantics/metrics/` — certified enterprise KPIs (e.g., Active Customer — 90-day canonical definition)
  - `contracts/datasets/` — certified enterprise dataset contracts (e.g., Customer master dataset)

- `domains/` — domain repos (owned by domain teams)
  - `finance/` — finance analytics domain
    - `datasets/` — finance transformation models
    - `contracts/datasets/` — finance dataset contracts (schema + grain + SLOs)
    - `semantics/models/` — finance semantic models (domain-scoped, lifecycle: shared)
    - `semantics/metrics/` — finance KPI definitions
    - `dependencies/` — platform package dependencies
  - `marketing/` — marketing analytics domain (second domain — illustrates cross-domain reuse)
    - `datasets/` — marketing transformation models (reuses enterprise.reporting.customer.v1)
    - `contracts/datasets/` — marketing dataset contracts
    - `semantics/models/` — extends enterprise.semantics.customer.v1 with marketing dimensions
    - `semantics/metrics/` — domain-local 30-day active customer metric (labeled local, not for exec reporting)
    - `dependencies/` — declares dry_platform_utils + dry_shared_macros as versioned dependencies

## Why the enterprise tier exists

The "Active Customer" divergence from Part 1 of the article is solved here.

- `enterprise.metrics.active_customer.v1` — certified 90-day window, owned by Data Governance.
- `marketing.metrics.active_customers_30d.v1` — domain-local 30-day variant for campaign targeting, explicitly labeled `lifecycle: local`.

Marketing extends `enterprise.semantics.customer.v1` with campaign-specific dimensions.
Finance references the same enterprise customer identity through dataset dependencies and joins.
Cross-domain reports use the enterprise metric. Domain-local variants are allowed but governed.

## Why contracts and semantics live under domains (and enterprise)

Domain contracts encode domain meaning and domain change cadence — domain teams own them.
The enterprise tier holds the cross-domain certified layer.
The platform layer handles distribution (packages) and enforcement (registry, CI gates).

## How the sample maps to the DRY operating model

| DRY Model concept | Sample location | What it demonstrates |
|---|---|---|
| DRY in Code | `platform/packages/python/`, `platform/packages/sql/`, `domains/*/ingestion/` | Versioned, dependency-managed callable logic; domain teams reuse generic utilities instead of rebuilding ingestion, retry, pagination, or flag helpers |
| DRY in Logic | `domains/*/datasets/`, `domains/*/contracts/` | Canonical dataset transformations with formal contracts; business rules defined once |
| DRY in Semantics | `domains/*/semantics/`, `enterprise/semantics/` | Governed metric and entity definitions; extension pattern (domain extends enterprise entity) |
| Artifact lifecycle spectrum | `domains/marketing/` (local) → `domains/finance/semantics/` (shared) → `enterprise/` (certified) | `local`, `shared`, and `certified` states with explicit governance expectations at each stage |
| DRY Artifact Registry — all interface types | `platform/registry/registered/` | callable_logic, queryable_dataset, and semantic_contract artifacts all registered; INDEX shows what is excluded and why |
| Runtime bypass detection | `platform/registry/observed/` | Warehouse/catalog observations compared to registered artifacts to detect shadow copies and bypasses |
| Build-time duplication prevention | `platform/ci/` | CI gates enforce metadata, compatibility, structural fingerprinting, and advisory semantic similarity |
| DRY measurement | `platform/metrics/` | Scorecard separates structural coverage (what is registered) from behavioral adoption (what is actually queried) |
| Multi-repo simulation | `platform/`, `enterprise/`, `domains/*/` | Folders stand in for separate repositories owned by different teams |

## Framework- and tool-agnosticism

- **Transformation frameworks** map onto `domains/*/datasets/`.
- **Execution engines** (Spark) are runtime environments, not build tools; they consume versioned packages from `platform/packages/`.
- **Semantic layers** (MetricFlow, Cube, Looker) serve as runtime for `semantics/models/` and `semantics/metrics/` definitions.