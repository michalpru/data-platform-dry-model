# CI enforcement (DRY promotion gates)

This folder contains the CI/CD gate workflow that enforces DRY lifecycle policy at promotion time.

## Principle

Reuse compliance is a build-time concern, not a review discipline.  
Gates run on pull requests that modify shared or certified artifact declarations (contracts, semantics, enterprise/).

## Lifecycle-differentiated enforcement

| Lifecycle state | Gate 1: Metadata | Gate 2: Compatibility | Gate 3: Duplication | Advisory: Similarity |
|---|---|---|---|---|
| `local`     | skipped  | skipped  | skipped         | skipped  |
| `shared`    | blocking | blocking | flagging (warn) | advisory |
| `certified` | blocking | blocking | blocking        | advisory |

Only artifacts declared as `shared` or `certified` trigger gates.  
Domain-local implementation details (`lifecycle: local`) are excluded to avoid coordination overhead.

## Gate sequence

```
1. Metadata gate         → owner, FQN, lifecycle state present           [blocking: shared + certified]
2. Compatibility gate    → no breaking changes without version bump       [blocking: certified]
3. Duplication gate      → structural fingerprint vs registry             [blocking: certified | warn: shared]
4. Similarity advisory   → embedding-based approximate match             [flag only — never blocks]
5. Registry publish      → on merge: parse manifests, publish to registry control plane
```

## Enforcement calibration

Apply strongest enforcement where semantic inconsistency costs exceed coordination costs:

- **`certified`** — enterprise metrics, Tier-1 executive reporting, cross-domain KPIs
- **`shared`** — team-shared utilities, transformation packages, domain datasets
- **`local`** — exploratory work, one-off transforms, domain-internal logic (no gates)

Friction signals (exceptions, forks to avoid upstream change) are architectural signals —
they indicate incomplete lifecycle guarantees or controls that create more friction than value.

See: `model-docs/07-reuse-enforcement.md` and Part 3, Section 2.4 of the article.

## Reference workflow

See `dry-promotion-gate.yml`.

## Duplication detection policy

See `duplication-detection-policy.yaml` for a tool-agnostic policy separating deterministic structural checks from advisory semantic similarity. This mirrors the model rule: exact/high-confidence structural matches can block promotion; embedding and LLM-based similarity remain advisory.
