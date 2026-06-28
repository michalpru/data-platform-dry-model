# Platform layer (organization-wide shareables)

The platform layer contains assets that should be **shared across many domains**.

In this reference structure, `platform/` means **organization-wide shareables**.  
Some orgs name this folder `shared/` or `platform_shared/` — the key is the ownership boundary, not the label.

Typical ownership:
- Data Platform Team / Analytics Platform Team / Engineering Guild

## What the platform publishes

| Folder | What it holds | Consumed how |
|---|---|---|
| `packages/sql/` | Publishable SQL template macro package | Referenced in a domain package manifest via git or internal registry |
| `packages/python/` | Publishable Python wheel (`pyproject.toml`) | Referenced in `requirements.txt` via PyPI or private registry |
| `registry/` | Registered artifacts and observed runtime objects | Queried by CI gates, discovery tools, and impact analysis |
| `ci/` | Promotion gates and duplication policy | Runs at build time before shared/certified artifacts are promoted |
| `metrics/` | Reuse scorecard definitions | Measures structural coverage and behavioral adoption |

The reference repo intentionally models reusable callable logic as **versioned packages**.
That keeps the sample aligned with the whitepaper concepts: stable reuse interfaces,
declared dependencies, lifecycle metadata, compatibility rules, and registry visibility.

Examples:
- `dry_platform_utils.ingestion` — generic REST ingestion control flow reused by Finance and Marketing.
- `dry_platform_utils.transforms` — generic transformation helpers.
- `dry_shared_macros` — SQL template helpers consumed through a package dependency.

Non-goal:
- domain-specific business meaning (that belongs to domains and semantic ownership)

## Why registry, CI, and metrics live here

These capabilities are platform-owned because they cross repository and domain boundaries:

- the registry provides shared discovery and impact analysis
- CI gates enforce lifecycle, compatibility, and duplication policy at promotion time
- metrics combine declarations, dependency graphs, query logs, and semantic telemetry into reuse adoption signals
