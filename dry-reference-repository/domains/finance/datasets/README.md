# Finance datasets (queryable datasets)

Put transformation models here (tables/views) that become the canonical queryable interface.

Examples of what belongs here:
- SQL transformation models
- SQL transformations that materialize into curated tables

Principles:
- datasets expose a stable consumption interface (the “default path”)
- shared/certified datasets should have contracts in `../contracts/datasets/`
- shared/certified datasets should have a registry entry
