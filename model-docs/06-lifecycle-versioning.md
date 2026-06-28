# Lifecycle and versioning policy (local → shared → certified → deprecated → retired)

This doc provides a tool-agnostic policy to make reuse safe and enforceable.

## Lifecycle states

### Local
- Purpose: rapid iteration inside a team or domain.
- Allowed: breaking changes, renames, refactors.
- Enforcement: none (no duplication blocking).

### Shared
- Purpose: declare reuse intent and expose a stable interface.
- Required metadata:
  - owner
  - interface type(s)
  - logical identity (FQN)
  - version scope
- Enforcement: blocking compatibility gates; duplication is flagged for advisory review; interface drift requires versioning discipline.

### Certified
- Purpose: platform contract for business-critical assets.
- Additional requirements:
  - compatibility guarantees
  - impact analysis (dependency graph)
  - deprecation windows
  - stricter promotion approvals
- Enforcement: blocking CI gates + runtime guardrails (where possible).

### Deprecated
- Purpose: signal that a certified artifact is superseded and scheduled for removal.
- Required metadata: `deprecated_since`, `replacement`, `removal_after`, and a consumer migration path.
- Transition requires Governance Council approval and a registered replacement.
- Enforcement: existing consumers are supported through the sunset window; new adoption is blocked.

### Retired
- Purpose: remove the artifact from active use once the sunset window closes.
- An immutable record and successor link are preserved.
- Enforcement: new references are blocked at build and runtime.

## Lifecycle transitions

- **Local → Shared**: declared by the owning team when reuse intent is established.
- **Shared → Certified**: requires Governance Council approval (validates compatibility guarantees, versioning, and deprecation policy).
- **Certified → Deprecated**: requires Governance Council approval, a registered replacement, a sunset window, and a consumer migration plan.
- **Deprecated → Retired**: occurs after the sunset window closes.

## Identity and versioning

A reusable artifact must have a **logical identity** independent of its physical implementation.

Recommended naming:
- `domain.namespace.name.v{N}` (example: `finance.reporting.revenue_events.v1`)
- `enterprise.namespace.name.v{N}` (example: `enterprise.metrics.active_customer.v1`)

**Namespace conventions:**
- `domain.*`: domain-scoped artifacts (owned by domain teams)
- `enterprise.*`: cross-domain certified artifacts (owned by Data Governance)
- `platform.*`: platform-layer utilities and packages

**Avoid:**
- Mixed physical/logical namespaces in the FQN (e.g., `finance.marts.*` is a physical schema reference; `finance.reporting.*` is the correct logical namespace for a reporting artifact).

Version increments are required for:
- schema changes (datasets)
- signature changes (callable logic)
- semantic meaning changes (metrics/semantic contracts)

## Compatibility rules differ by interface

- **Callable logic**: signature + behavior contract
- **Queryable datasets**: schema + grain + SLA + contract semantics
- **Semantic contracts**: semantic model structure, metric definitions, filters, grain, and allowed dimensions

## Deprecation

Certified artifacts should define:
- `deprecated_since`
- `replacement`
- `removal_after`

This reduces defensive forking by making change propagation predictable.

**Enterprise-scoped deprecation**: changes to enterprise-scoped certified artifacts require Governance Council approval and a governed deprecation window. Domain teams must migrate to the new version before the old version's `removal_after` date. This approval requirement must be documented in the artifact manifest itself (see `enterprise.metrics.active_customer.v1.yaml` for an example).

## Deprecation notice distribution (known gap)

Lifecycle policy defines *when* an artifact is deprecated. A related unsolved problem is *how downstream consumers learn about it*.

In API governance this is partially solved: deprecation headers signal impending removal, and automated dependency-update tools (Dependabot, Renovate) open pull requests in consumer repos. In data platforms, the equivalent requires the registry's consumer graph:
- When a certified artifact enters deprecation, the registry identifies all dependent teams via `consumers[]`.
- Automated notifications (PRs in consumer repos, Slack alerts, JIRA tickets) are generated from that graph.

Most platforms have not yet built this loop from producer intent to consumer awareness. Building it is a Stage 3 investment (see staged adoption in `05-artifact-registry-spec.md`). Acknowledging this gap explicitly helps teams understand where governance breaks down in practice and where to prioritize investment.
