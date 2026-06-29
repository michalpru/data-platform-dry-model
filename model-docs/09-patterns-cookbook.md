# Patterns cookbook (implementation-agnostic)

This is a curated list of patterns referenced by the DRY Model.

## Pattern: Reuse maturity assessment (Phase I)
- Goal: evaluate reuse before enforcing it; locate structural gaps and set target maturity per layer and reuse interface.
- Method: score artifacts and interfaces against the 13 DRY Quality Attributes (Engineering Enablement, Governance and Operability, Organizational Semantic Alignment); rate Operational Maturity M0-M3 per attribute.
- Output: structural gaps (missing lifecycle controls, weak discoverability, duplicated logic, insufficient semantic enforcement, no consumption visibility) that prioritize where to invest first.
- Note: capability (attributes present) is distinct from operational maturity (reuse actually happening) - a macro that is copy-pasted instead of referenced stays M0.
- Reference: `03-quality-attributes.md`, `04-operational-maturity-assessment.md`

## Pattern: Versioned artifact identity (FQN)
- Goal: stable logical identity across environments and physical implementations.
- Naming: `domain.namespace.name.vN` (domain), `enterprise.namespace.name.vN` (cross-domain), or `platform.namespace.name.vN` (platform utilities)
- Avoid mixing physical schema names in the FQN (e.g., `finance.marts.X` = physical; `finance.reporting.X` = logical)
- Template: `templates/artifact-manifest.yaml`

## Pattern: Local to shared to certified lifecycle gates
- Goal: reduce defensive forking by creating predictable compatibility guarantees.
- Key: gate strength increases with lifecycle state; local artifacts have no gates.
- Reference: `06-lifecycle-versioning.md`

## Pattern: Enterprise tier for cross-domain semantics
- Goal: resolve "Active Customer"-style divergence across domains by certifying one definition at the organizational level.
- Structure: `enterprise/semantics/models/`, `enterprise/semantics/metrics/`, `enterprise/contracts/datasets/`
- Ownership: Data Governance, approved by the Governance Council, not domain teams or platform team
- Domain teams extend enterprise entities (`extendsModel:`) with domain-specific dimensions rather than redefining the entity
- Domain-local variants are allowed but labeled `lifecycle: local` with explicit pointer to the certified equivalent (`seeAlso.certified:`)
- Example: `enterprise.metrics.active_customer.v1` (90-day, certified) + `marketing.metrics.active_customers_30d.v1` (30-day, local)
- Reference: `../dry-reference-repository/enterprise/`

## Pattern: Domain-extends-enterprise semantic model
- Goal: add domain-specific dimensions to a certified entity without redefining its grain or standard dimensions.
- Implementation: `extendsModel: enterprise.semantics.customer.v1` in the domain semantic model YAML
- Effect: domain model inherits grain + standard dimensions; adds campaign/churn/marketing-specific dimensions
- Example: `../dry-reference-repository/domains/marketing/semantics/models/marketing.semantic.customer.v1.yaml`

## Pattern: DRY Artifact Registry (staged rollout)
- Goal: unify discovery and enforcement signals across repos without requiring immediate database infrastructure.
- Stage 1: YAML manifests in source control, `INDEX.md` snapshot, schema validation on PR
- Stage 2: Lightweight queryable store populated by CI, enabling cross-repo impact analysis and consumer graph
- Stage 3: Runtime enrichment (consumption-time adoption and bypass signals)
- Registry entries use `sourceManifest:` / `promotedFrom:` to link back to domain declaration (source of truth)
- Org-scope rule: only `shared`/`certified` artifacts are registered; domain-local stays in domain repo
- Reference: `05-artifact-registry-spec.md`, `../dry-reference-repository/platform/registry/`

## Pattern: DRY Promotion Gate (CI/CD)
- Goal: make reuse compliance a build-time concern, not a review discipline.
- Gate sequence: metadata, compatibility, structural fingerprint, advisory similarity, registry publish
- Lifecycle-differentiated: `local` = skipped; `shared`/`certified` = blocking lifecycle and compatibility checks
- Duplication signals (including high-confidence structural matches) never block on their own: they route to required review or exception approval, and promotion is blocked only when required review evidence or exception rationale is missing
- SQL structural fingerprinting is same-dialect only (not a cross-dialect solved problem)
- Embedding similarity is advisory-only; never blocks
- Reference: `07-reuse-enforcement.md`, `../dry-reference-repository/platform/ci/dry-promotion-gate.yml`

## Pattern: Multi-repo registry (cross-repo governance)
- Goal: apply DRY governance across separate domain, platform, and enterprise repositories.
- The registry is most valuable in multi-repo environments: it provides the cross-repo discovery and impact analysis that grep across local folders cannot.
- CI gates trigger on PRs in any participating repo; all publish to the shared registry API/index.
- The monorepo reference (`../dry-reference-repository/`) co-locates layers for readability only.

## Pattern: Deterministic vs advisory enforcement
- Goal: separate what blocks from what routes to review; never auto-block on duplication.
- Blocking (deterministic lifecycle and compatibility): missing owner/FQN/lifecycle metadata, FQN collision, breaking change without version increment, references to deprecated/retired versions
- Route to required review or exception (deterministic duplication, never auto-blocks): structural fingerprint, normalized SQL hash (same dialect), signature equivalence, schema-equivalence matches
- Advisory (flag only): embedding similarity, LLM-assisted reasoning, cross-dialect comparison
- Promotion is blocked only when required review evidence or exception rationale is missing
- Reference: `07-reuse-enforcement.md`

## Pattern: Calibrate enforcement by asset criticality
- Goal: match enforcement strength to the cost of inconsistency rather than applying a uniform bar.
- Key: observe broadly, enforce narrowly - the certified population that warrants M3 enforcement should be intentionally small.
- Apply strongest enforcement to cross-domain certified artifacts and Tier-1 reporting; leave domain-local and exploratory assets ungated.
- Friction signals (exceptions, forks to avoid upstream change, shadow implementations) are architectural-gap signals, not policy violations.
- Reference: `07-reuse-enforcement.md`

## Pattern: Justified duplication and exceptions
- Goal: treat duplication as a governed decision, not an automatic failure.
- Key: some duplication is legitimate (domain-specific divergence, performance/isolation, transitional migration); record it instead of silently forking.
- Mechanism: justified reimplementations are tracked as registry exceptions with explicit rationale and, where relevant, a pointer to the canonical equivalent (`seeAlso.certified:`).
- This is why duplication signals route to review/exception rather than hard-blocking.
- Reference: `06-lifecycle-versioning.md`, whitepaper "When Duplication Is Justified"

## Pattern: Semantic adoption telemetry
- Goal: measure behavioral reuse and bypass.
- Reference: `08-adoption-metrics.md`

## Pattern: Gold path consumption
- Goal: make the intended interface the easiest way to do the right thing.
- Implementation examples:
  - workspace restrictions for Tier-1 reporting
  - access control to raw data for broad analyst populations
  - certified semantic endpoints

## Pattern: Dependency-based reuse (packages)
- Goal: make callable logic reuse explicit via dependency management, not copy/paste.
- Python: `pyproject.toml` publishes a wheel; domain `requirements.txt` declares a version pin
- dbt: `dbt_project.yml` publishes a package; domain `packages.yml` declares a version pin
- The lifecycle in `logic/` (source-level) to `packages/` (distributable) mirrors the software engineering package release model
- Reference: `../dry-reference-repository/platform/packages/`

## Pattern: Canonical-source tracing for materialized assets
- Goal: govern physical duplication so every materialized copy is controlled, not eliminate materialized copies.
- Invariant: each materialized asset either is a declared canonical source or traces to one via lineage, and is itself owned, observable, and registered.
- Reuse rule: before creating a new physical copy, reuse an existing materialization that already satisfies the required grain, partitioning, or refresh frequency.
- Failure mode addressed: uncontrolled, uncoordinated duplication of physical outputs (rising cost, ambiguous canonical dataset).
- Reference: `02-platform-artifacts-and-reuse-interfaces.md`