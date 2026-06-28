# Finance domain (example)

This domain owns:
- canonical datasets for finance use cases
- finance semantic models and finance metrics

It consumes platform-provided shared utilities and policies.

## Repository mental model (per the DRY article)

- `datasets/` exposes **queryable datasets** (DRY in Logic / DRY in Physical Assets)
- `contracts/datasets/` declares **dataset interface contracts** (schema, grain, SLOs)
- `semantics/models/` declares **semantic models** (entities + grain + relationships)
- `semantics/metrics/` declares **metrics** (KPI definitions)

The goal is that consumers reuse **interfaces** (datasets and metrics), not re-implement logic.
