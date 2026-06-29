# Enforcement in CI/CD (promotion gates)

Reuse Enforceability, evaluated in Phase I, measures how strongly artifacts or interfaces make reuse the natural or lowest-friction path. Reuse Enforcement, introduced here, is the operational layer that acts on that structural potential through registry-backed resolution, CI/CD gates, authoring-time signals, and lifecycle policies.

Reuse does not emerge from structure alone, but it must be actively enforced. Even when artifacts provide strong support for DRY Quality Attributes such as abstraction, composability, and reuse enforceability, consistent reuse is not guaranteed in practice. Without enforcement, teams can bypass intended interfaces, reimplement logic, or introduce divergent definitions.

DRY becomes enforceable when checks run automatically in promotion workflows.


## Lifecycle-differentiated enforcement summary

| Lifecycle state | Gate 1: Metadata | Gate 2: Compatibility | Gate 3: Duplication | Advisory: Similarity |
|---|---|---|---|---|
| `local`     | skipped  | skipped  | skipped         | skipped  |
| `shared`    | blocking | blocking | review/exception (no auto-block) | advisory |
| `certified` | blocking | blocking | review/exception (no auto-block) | advisory |

Only `shared` and `certified` artifacts trigger gates. Domain-local logic is excluded to avoid coordination overhead.

## Gate types

### 1) Metadata gates (shared/certified)
Block promotion if:
- owner is missing
- artifact identity (FQN + version) is missing
- lifecycle state is missing

### 2) Compatibility gates (shared/certified)
Block promotion if:
- breaking schema/signature/semantic changes occur without version increment
- deprecation windows are missing for replacements

**Compatibility rules by interface type:**
- `queryable_dataset`: schema + grain + SLOs + contract semantics
- `callable_logic`: function signature + behavior contract
- `semantic_contract`: semantic model structure, metric definitions, filters, grain, and allowed dimensions

### 3) Structural duplication detection (shared/certified)

Deterministic, structure-based detection:

- **Structural fingerprinting** (deterministic, same dialect):
  - Normalize SQL: strip whitespace, lowercase, normalize aliases, then hash
  - SQL AST normalization with tools such as SQLGlot detects equivalent transformations independent of formatting. **Note: cross-dialect AST equivalence is not solved.** Apply within a single warehouse dialect only. Dialect-specific constructs, optimizer behavior, and alternative query formulations can produce different ASTs for logically equivalent transformations. As a result, structural fingerprinting cannot reliably detect all cases of equivalent logic, particularly in cross-dialect environments.
  - Python structural hash via the `ast` module: `hashlib.sha256(ast.dump(ast.parse(source)).encode())`
  - Normalized schema equivalence for datasets (sorted field names, types, grain)

A high-confidence structural match does not block promotion by itself for either `shared` or `certified` artifacts; it routes the artifact to required human review or exception approval. Promotion is blocked only when the required review evidence or exception rationale is missing.

### 4) Semantic similarity detection (advisory)

Non-deterministic checks that flag but never block:
- Embedding-based similarity (pgvector / Qdrant / Pinecone): approximate comparison across descriptions, field names, and business terms
- LLM-assisted reasoning: useful for cross-language / cross-dialect cases; non-deterministic behavior limits use to advisory workflows

A policy threshold determines when to flag. Flagged cases enter lightweight human review: PRs receive an advisory comment and teams must acknowledge or justify before merge; promotion is not blocked.

## Calibration

Apply strongest enforcement where semantic inconsistency costs exceed coordination costs:
- Cross-domain certified artifacts and Tier-1 executive reporting → highest enforcement
- Shared domain artifacts → duplication warnings + compatibility blocking
- Local / exploratory assets → no gates

Friction signals (exceptions, forks to avoid upstream change, shadow implementations) are **architectural gap signals**, not policy violations. They typically indicate incomplete lifecycle guarantees or controls that create more friction than value. Over-enforcement pushes teams toward shadow implementations; the registry observes broadly but enforces narrowly.

## Runtime enforcement (access control)

Runtime enforcement uses access policy to make governed consumption paths the default, guiding consumers toward curated data products and certified definitions rather than raw or intermediate datasets.

A structural caveat applies: native warehouse access control governs *objects* - tables, views, and columns - not *definitions*. It can grant or deny access to a physical object, but it cannot express "compute this metric only through its certified logic." As long as consumers retain read access to the underlying base tables, they can re-implement a metric with different filters, grain, or aggregation, and the warehouse will execute it as a valid query. Enforcing a certified definition at runtime therefore requires a mediating layer that makes the governed computation the only reachable path: governed views that embed the canonical logic while base-table access is revoked, or a data service/API that holds the sole underlying grant. Without one of these, runtime "certified-only" degrades to convention.

## Recommended pipeline stages (tool-agnostic)

1. Validate manifests and metadata
2. Check compatibility (breaking changes vs version)
3. Generate structural fingerprint
4. Compare fingerprint against registry (route matches to required review/exception; do not block on the match itself)
5. Run advisory similarity checks (embedding / LLM, flag only)
6. Publish registry update (on merge to main)

## Reference implementation

See `dry-reference-repository/platform/ci/dry-promotion-gate.yml` for an annotated GitHub Actions workflow stub implementing all six stages with `TODO:` annotations for tool wiring.