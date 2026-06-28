# Glossary

## DRY Layers (reuse surfaces)

- **DRY in Code**: reuse of technical utilities (ingestion helpers, merge utilities, hashing, generic transformations).
- **DRY in Logic**: reuse of canonical business transformations that define shared datasets or attributes.
- **DRY in Semantics**: reuse of governed meaning (entities, grain, relationships, metrics/KPIs).
- **DRY in Materialization (Physical Data Assets)**: controlled materialization that preserves one canonical definition while allowing intentional, governed physical copies to meet latency, grain, or refresh-frequency requirements.

## Reuse interfaces

- **Callable logic**: reused by engineers in pipelines (functions/macros/UDFs).
- **Queryable datasets**: reused through stable SQL interfaces (models, curated tables, views).
- **Semantic contracts**: reused through governed definitions (semantic models, metrics).

## Structural vs behavioral reuse

- **Structural reuse**: whether artifacts are defined once and referenced (dependency counts, lineage reuse).
- **Behavioral reuse**: whether consumers adopt the intended consumption interface or bypass it (query logs, semantic telemetry, BI metadata).

## Lifecycle states

- **Local**: team-scoped; changes can be fast. Not registered in the DRY Artifact Registry. Annotate with `lifecycle: local` and add `note: "Intentionally local; certified equivalent: <fqn>"` when a certified version exists.
- **Shared**: reuse intent declared; stable interface expected.
- **Certified**: platform contract; explicit compatibility guarantees and stricter gates.
- **Deprecated**: superseded by a registered replacement; existing consumers are supported during a sunset window, but new adoption is blocked. The owner declares `deprecated_since`, the replacement version, and `removal_after`.
- **Retired**: removed from active use; an immutable record and successor link are preserved, and new references are blocked at build and runtime.

## Enterprise tier

The **certified, cross-domain scope** of the lifecycle model: certified semantic and dataset definitions whose scope spans the entire organization, owned by the Data Governance function. This is not a separate model layer; it is the `certified` lifecycle state applied at organization-wide scope.

- Domain teams are *consumers*, not owners, of enterprise-scoped artifacts.
- New versions require compatibility review and Governance Council approval.
- Examples: `enterprise.semantics.customer.v1`, `enterprise.metrics.active_customer.v1`.
- See: `dry-reference-repository/enterprise/`.

Distinct from **platform layer**: the platform layer provides distribution mechanisms (packages, CI gates, registry); enterprise-scoped artifacts provide governed cross-domain meaning.

## Semantic model vs metric

These are structurally distinct artifact kinds (kept separate in the sample repo):

- **Semantic model** (`semantics/models/`): defines an entity's *structure*: grain, dimensions, relationships. Example: `enterprise.semantics.customer.v1` declares that `customer_id` is the grain and `last_activity_date` is a dimension.
- **Metric** (`semantics/metrics/`): defines a *calculation* built on a semantic model: type (sum/count_distinct), expression, filters, time grain. Example: `enterprise.metrics.active_customer.v1` is a `count_distinct(customer_id)` with a 90-day filter applied to the Customer model.

Tools such as MetricFlow (dbt), Cube, and Looker make this separation explicit in their schemas; the DRY model follows the same structure.

- **Canonical**: intended “default path” within a scope (domain or platform).
- **Certified**: canonical + explicit compatibility policy + ownership + enforcement.

## Dataset contract

A machine-readable declaration of a queryable dataset's **consumer-facing interface**: grain, schema, SLOs (freshness/availability), and semantic field notes.

**A queryable dataset artifact in the DRY model has two separable components:**
- **Transformation implementation**: the SQL model, view, or materialized table: *how* the data is produced. This is governed for duplication, portability, and lifecycle, but is not what a dataset contract primarily describes.
- **Dataset contract** (this document kind): the *physical* interface commitment: schema, grain, and quality guarantees (SLOs). This is the layer addressed by data contract specifications and validation workflows.

Note: the full consumer interface for a dataset spans two layers:
1. The dataset contract: physical interface (schema, grain, freshness).
2. The semantic model built on top of it: semantic interface (entity meaning, dimensions, relationships, metrics). This is partially covered by the semantic contracts layer (`semantics/models/`, `semantics/metrics/`) and is outside the primary scope of dataset contract enforcement.

Dataset contracts govern the consumer-producer interface for queryable datasets. Open specifications such as the Open Data Contract Standard (ODCS) formalize this layer. They do not govern transformation implementation reuse, structural duplication of SQL logic, or cross-team semantic alignment by themselves. Those concerns belong to the DRY Artifact Registry, lifecycle policy, semantic contracts, and enforcement gates.

Organizations already using data contract tooling can use those contract definitions as part of the DRY registry's interface declaration layer, while the DRY model adds governance of transformation implementation, semantic stability, lifecycle, and reuse enforcement.

## Duplication hotspot

A cluster of assets that appear to implement the same concept (by name, schema similarity, lineage similarity, or semantic similarity). Hotspots are signals; they may be valid divergence or uncontrolled forks.
