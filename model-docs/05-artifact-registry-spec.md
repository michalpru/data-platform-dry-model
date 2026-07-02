# DRY Artifact Registry: minimal control plane spec

The DRY Artifact Registry is a **reuse-control index**, not a general-purpose catalog.

The DRY Artifact Registry tracks whether datasets, transformation logic, and semantic contracts represent canonical, governed definitions: which artifact is canonical for a concept, what its lifecycle state is, and who is bypassing it. **This sets it apart from adjacent tooling:**

- Data observability platforms monitor data quality: anomalies, schema drift, freshness, and pipeline reliability - that is, whether shared datasets are operationally reliable.
- Data catalogs answer what data exists, its lineage, and who owns it. The Registry treats them as a signal source and adds a reuse-governance overlay.

## Purpose

- Unify discovery and lifecycle governance for reusable artifacts across:
  - code repos (packages/macros)
  - transformation frameworks (models/DAGs)
  - warehouse catalogs (tables/views/UDFs)
  - semantic layer inventories and telemetry

## Two-layer architecture

The registry operates as two complementary layers with different purposes:

### Layer 1: Declaration layer (YAML in source control)

YAML manifest files per artifact, stored in the repo that owns the artifact.

Purpose:
- Declare reuse intent, ownership, FQN, lifecycle state, interface type, compatibility policy
- Version-controlled (diffable, reviewable in PRs, change-tracked with git history)
- Input to CI gates at promotion time
- **Source of truth** for registry declaration data

This is the natural starting point (zero additional infrastructure). See `templates/artifact-manifest.yaml`.

### Layer 2: Runtime control plane (queryable store)

A lightweight database or API service that aggregates YAML declarations + runtime signals.

Purpose:
- Cross-repo search and discovery
- Dependency graph traversal across dependent artifacts (impact analysis for breaking changes)
- Runtime bypass detection (observed objects from warehouse catalogs, query logs)
- Measurement dashboards (reuse rate, duplication hotspots, adoption vs bypass)

What YAML alone cannot do: query which 40 dependent artifacts will break if I change `v1`, or detect that a new transformation in repo B is structurally equivalent to one already certified in repo A.

**Database technology choices** (in order of adoption complexity):
- Relational store (Postgres) or document store (MongoDB / Azure Cosmos DB): sufficient for artifact identity + metadata + dependency graph
- Graph database (Neo4j, AWS Neptune): natural evolution once the consumer/producer graph is complex (many cross-domain dependencies)
- Vector store (pgvector, Qdrant, Pinecone): only needed for semantic similarity detection (optional advanced capability)

**Multi-repo environments**: the registry is most valuable when domains live in separate repositories. It provides the cross-repo discovery and impact analysis that `grep` across local folders cannot deliver.

## Staged implementation

### Stage 1: YAML-only registry (zero infrastructure)
- YAML manifests per artifact in domain-owned repositories
- `platform/registry/registered/INDEX.md` snapshot updated by CI on merge
- CI step validates manifest schema on every PR

### Stage 2: Aggregated API (lightweight queryable store)
- CI step parses merged manifests and POSTs to a registry API/DB
- DB stores the entity model below: `artifact`, `implementation_binding`, `dependency_edge`, and (once behavioral feeds are added) `consumer` and `usage_edge`; dependency and consumer counts are derived aggregates
- REST API: `/artifacts?fqn=finance.*`, `/impact?fqn=finance.reporting.revenue_events.v1`
- Enables cross-repo impact analysis and consumer notification

### Stage 3: Runtime enrichment
- Warehouse catalog export → Observed Objects feed → bypass detection
- Semantic layer telemetry → behavioral reuse measurement
- Optional: embedding similarity pipeline for semantic duplication detection

## Organizational scope rule

**Not all artifacts belong in the registry.** Only `shared` and `certified` artifacts are registered.

- **Domain-local artifacts** (`lifecycle: local`) stay in their domain repo. Not registered.
- **Domain-owned certified artifacts** (e.g., `finance.reporting.revenue_events.v1`): the Finance team owns the definition; the registry records it. Ownership does not transfer to the platform team.
- **Enterprise-scoped certified artifacts** (e.g., `enterprise.metrics.active_customer.v1`): certified at organization-wide scope; apply cross-domain; any version change requires Governance Council approval.

The `promotedFrom` / `sourceManifest` annotation in registry YAML entries makes explicit which domain manifest was the source: the registry entry is derived from, not a duplicate of, the domain manifest.

See: `dry-reference-repository/platform/registry/registered/` for annotated examples.

### 1) Artifact identity
Each artifact has a stable logical identity:
- `interface_type` (callable_logic | queryable_dataset | semantic_contract)
- `fqn` (domain-scoped, versioned): use logical namespace, not physical schema name
- `version`

Physical implementations (multiple) map to a single identity.

### 2) Registered vs observed objects
Two orthogonal axes classify every entry: `entry_role` (`artifact` | `consumer`) and `registration_source` (`declared` | `observed`).
- **Registered**: artifacts explicitly declared as shared/certified (`entry_role = artifact`, `registration_source = declared`).
- **Observed**: objects and consumers discovered from catalogs/DAGs/logs that are not declared (`registration_source = observed`).
  - Observed artifacts provide bypass signals and duplication hotspot discovery; observed consumers anchor usage edges.

## Minimal data model (recommended)

The registry is a small graph of entities, not a single flat record. Counts (`dependencies[]`, `consumers[]`) are convenience aggregates derived from the edge tables below, not the primary model.

### `artifact` (registered entries)
Required fields:
- `artifact_id` (registry internal)
- `fqn`
- `interface_type`
- `entry_role` = `artifact`
- `registration_source` = `declared` | `observed`
- `lifecycle_state` (`shared` | `certified` | `deprecated` | `retired` for registered artifacts; `local` may appear in source manifests and on observed/local entries, but is not promoted into the governed registry scope)
- `reuse_scope` (`enterprise_canonical` | `shared_utility` | `domain_canonical`)
- `owner` (team + escalation)
- `source_system` (repo/warehouse/semantic tool)

Optional (advanced) fields:
- `semantic_summary`
- `embedding_vector_ref`

### `consumer` (observed entries)
Observation-only nodes captured from behavioral feeds (see Consumer node capture). Carry no governance attributes.
- `consumer_key`, `consumer_type`, `source_system`, `owner?`, `first_seen`, `last_seen`

### `implementation_binding` (physical-to-logical mapping)
The operational join key that resolves observed physical objects and query logs to a logical artifact:
- `artifact_fqn` (FK to artifact)
- `source_system`
- `physical_ref` (env-normalized object identifier)
- `environment`
- `object_type` (table | view | model | udf | package | function | metric_definition)
- `structural_hash` (AST-derived, per implementation)
- `binding_confidence`
- `valid_from`, `valid_to`

### `dependency_edge` (declared and derived)
- `from_fqn`, `to_fqn`, `source` (`declared` | `derived`)

### `usage_edge` (behavioral)
One row per (consumer, artifact) pair; see Usage edge fields.
- `consumer_key`, `artifact_fqn`, `usage_type` (`canonical` | `bypass`), `event_count_30d`, `last_seen`

### `duplication_candidate` (derived structural signal)
Persisted record of a suspected reimplementation between two artifacts. Similarity detection (structural hashing, embeddings) is the technique; the candidate edge is what the registry stores.
- `artifact_a`, `artifact_b`, `method` (`structural` | `embedding` | `llm`), `score`, `status` (`open` | `consolidated` | `tolerated`)

## Ingestion sources

- CI/CD builds publish:
  - declared artifacts (manifest)
  - dependency graph snapshots
  - test results / quality gates
- Warehouse catalog feeds publish:
  - tables/views/UDF inventory + last updated
- Semantic layer publishes:
  - semantic object inventory + usage telemetry
- Repository scanning / AI-assisted analysis enriches the observation layer with:
  - candidate callable logic, SQL transformations, semantic summaries, signatures, and similarity clusters
  - outputs flag candidates for promotion review; lifecycle state is not assigned automatically

## What you measure with the registry

Structural signals:
- dependency/consumer counts
- reuse concentration (top N certified assets)
- duplication hotspots (schema/lineage similarity)

Behavioral signals:
- adoption vs bypass (semantic telemetry, query logs, BI metadata)

Attribution-quality signals (prerequisite for trusting the above):
- `unattributed_event_count` and `unknown_consumer_count` (events routed to `unknown:{source_system}`)
- `% attributed` per source system
- `% object-resolved`: share of events whose physical object resolved to an artifact via implementation bindings; unresolved objects limit bypass-detection completeness
- Unknowns are excluded from certified adoption and bypass rates to avoid false precision, but are tracked separately so missing tags and shared service accounts surface as a measurable gap rather than silent under-reporting.

## Consumer node capture (behavioral-feed ingestion)

Consumer nodes are never declared by manifest. They are **discovered on first sighting** during behavioral-feed ingestion and inserted automatically (first-seen registration).

### Sources

Consumer identity is derived from tags and metadata attached to activity events:

| Source | Consumer key signal |
|---|---|
| Snowflake query history | `QUERY_TAG` JSON: `{"app":"tableau","dashboard":"exec-revenue-overview"}` |
| BigQuery job metadata | Job labels: `dashboard=exec-revenue-overview` |
| Databricks query tags | Query tag annotations on SQL warehouse sessions |
| Tableau / Looker / Power BI telemetry | Native BI metadata API: workbook or dashboard URN |
| Semantic-layer telemetry | Semantic object invocation with caller identity |

Where no tag is present, ingestion falls back to session-level metadata (service account, application name). Unresolvable events are recorded under a synthetic key `unknown:{source_system}` and excluded from adoption and bypass reporting until a tagging policy is enforced.

### Ingestion steps

1. The ingestion job reads an activity event (query log row, BI telemetry event, semantic-layer invocation).
2. A stable consumer key is derived from the tag or metadata: `{type}:{source}/{name}`, e.g. `dashboard:tableau/exec-revenue-overview`.
3. The physical object referenced in the event is resolved to a canonical artifact via `Implementation Bindings`. If no binding resolves, the event contributes to bypass signal for that physical object.
4. If the consumer key does not yet exist in the registry, a consumer node is inserted (`Entry Role = consumer`, `Registration Source = observed`). On subsequent events the node is not re-created; only its `last_seen` timestamp is updated.
5. The usage edge `(consumer key) → (artifact fqn)` is upserted: insert on first occurrence, update per-day event buckets and `last_seen` on subsequent occurrences. The rolling 30-day count is recomputed from the buckets, not incremented as a single running total.

### Consumer node fields

A consumer node is minimal: only enough to identify it and anchor edges. It carries no governance attributes (no Lifecycle State, Reuse Intent, or Ownership Domain):

| Field | Example |
|---|---|
| `consumer_key` (stable id) | `dashboard:tableau/exec-revenue-overview` |
| `consumer_type` | `dashboard` \| `notebook` \| `pipeline` \| `service` |
| `source_system` | `tableau` |
| `owner` (if resolvable from BI metadata) | `finance-analytics` |
| `first_seen` | 2026-01-09 |
| `last_seen` | 2026-06-25 |

### Usage edge fields

Each edge represents one (consumer, artifact) pair. There is at most one edge per pair; activity volume is captured as counters on the edge, not as separate rows:

| Field | Notes |
|---|---|
| `consumer_key` | FK to consumer node |
| `artifact_fqn` | FK to artifact entry |
| `usage_type` | `canonical` (pointed at a registered artifact) or `bypass` (pointed at an unregistered physical object resolved to an observed artifact) |
| `event_count_30d` | Rolling 30-day count, recomputed from per-day buckets (not a running total) |
| `last_seen` | Timestamp of most recent event |

The `usage_type` field is what separates adoption aggregates (edges to canonical artifacts) from bypass aggregates (edges to non-canonical physical objects) in the behavioral signals reported to the whitepaper registry attribute.

### Promotion path

A consumer node remains observation-only unless it is also produced from structured logic reused by other consumers (e.g., a semantic model that other workbooks reference). At that point it can be promoted to an artifact entry (`Entry Role = artifact`) and assigned governance attributes. Promotion requires explicit declaration via manifest; lifecycle state is not assigned automatically.

