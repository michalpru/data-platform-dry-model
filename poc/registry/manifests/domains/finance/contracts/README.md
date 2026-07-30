# Finance dataset contracts

This folder contains **dataset interface contracts** for finance queryable datasets.

Contracts define:
- grain (dataset grain, not KPI aggregation rules)
- schema
- SLOs (freshness/availability)
- semantic notes (field meaning)

How this differs from `semantics/`:
- Dataset contracts describe a dataset’s *interface*.
- Semantic models + metrics define organization-wide meaning and KPI logic (DRY in Semantics).

Contracts are required for shared/certified datasets.
