# Templates

These templates provide tool-agnostic starting points for applying the **Data Platform DRY Model** in repositories, CI/CD pipelines, internal developer portals, and artifact registries.

The manifest templates are the concrete form of the **intent declaration** described in the whitepaper's [DRY Artifact Registry](../publications/whitepaper-data-platform-dry-model.md#dry-artifact-registry) section: reusable artifacts declared in source control, versioned and reviewable, and used by CI/CD to populate the registry.

They are intentionally lightweight. Their purpose is to make the main DRY operating concepts explicit:

- artifact identity through stable FQNs
- ownership and lifecycle state (`local`, `shared`, `certified`)
- reuse interface type (`callable_logic`, `queryable_dataset`, `semantic_contract`)
- compatibility expectations and versioning
- registry publication intent
- dependency declarations for impact analysis
- duplication detection and reuse measurement

The templates can be adapted to dbt, SQLMesh, Spark, semantic-layer tools, custom CI/CD pipelines, or internal platform catalogs.

## Template index

| Template | Primary DRY concept | Typical owner |
|---|---|---|
| `artifact-manifest.yaml` | Common artifact identity, lifecycle, registry, dependency, and implementation metadata | Platform, domain, or governance team |
| `reusable-logic.yaml` | DRY in Code / DRY in Logic through callable shared logic | Platform or domain engineering team |
| `dataset-contract.yaml` | Queryable dataset interface, schema, grain, SLOs, and materialization expectations | Domain or enterprise data product owner |
| `semantic-model.yaml` | Semantic contract for governed entities, dimensions, and measures | Domain or enterprise semantic owner |
| `metric.yaml` | Certified or domain-scoped metric definition | Data governance, analytics engineering, or domain owner |
| `duplication-detection-policy.yaml` | Build-time reuse enforcement and exception handling | Platform engineering |
| `reuse-scorecard.yaml` | Structural and behavioral reuse measurement | Platform engineering or data governance |

## How these templates map to the model

- **DRY in Code** is represented by reusable technical utilities and package-style callable logic.
- **DRY in Logic** is represented by reusable transformation logic, canonical datasets, and declared dependencies.
- **DRY in Semantics** is represented by semantic models and metric definitions.
- **DRY in Materialization (Physical Data Assets)** is represented by materialization expectations in dataset contracts and by Implementation Bindings (physical implementations) of a canonical artifact in artifact manifests.
- **Measurement** is represented by the reuse scorecard template.
- **Enforcement** is represented by the duplication-detection policy template.

Use these files as patterns, not as a mandatory schema. The field names are deliberately plain so they can be translated into the metadata model of a specific platform.

For `semantic-model.yaml` and `metric.yaml` specifically: the `spec` sections mirror dbt MetricFlow and SQLMesh structures for reference. In a dbt or SQLMesh platform, those tools own the authoritative implementation; the governance value in these templates is primarily in the registry and governance fields (`lifecycle`, `registry`, `fqn`, `compatibility`) and, for semantic models, cross-tool dependency fields such as `sourceDataset`. In an operational system, `spec` would be generated from the tool-native manifest rather than authored manually.
