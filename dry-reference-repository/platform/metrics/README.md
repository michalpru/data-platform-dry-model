# DRY reuse measurement examples

This folder shows how a platform team can define reuse metrics without hard-coding them into one BI tool or warehouse.

The scorecard separates two measurement types:

- **Structural metrics**: what the platform has made reusable by design, such as registered artifacts, dependency counts, and certified coverage.
- **Behavioral metrics**: what teams actually reuse at runtime, such as certified metric usage, dataset bypasses, and unregistered copies found in query logs or catalogs.

Use these metrics to decide whether to promote, consolidate, tolerate divergence, or improve lifecycle/discoverability controls.