# Decision Guides

These checklists help practitioners apply the Data Platform DRY Model during architecture reviews and governance discussions. They turn the model's concepts into decision prompts for everyday use.

## 1. Should this artifact be local, shared, or certified?

| Question | If yes | Suggested lifecycle |
|---|---|---|
| Is it only useful inside one team or experiment? | Keep coordination overhead low. | `local` |
| Will other teams or production pipelines depend on it? | Declare owner, FQN, version, and interface. | `shared` |
| Does inconsistency affect executive reporting, regulatory reporting, cross-domain KPIs, or Tier-1 decisions? | Add compatibility guarantees, impact analysis, approvals, and stronger gates. | `certified` |
| Is there already a certified equivalent? | Keep this local only if it has a scoped reason and points to the certified artifact. | `local` with `seeAlso.certified` |

## 2. Which reuse interface should this expose?

| If the main need is... | Prefer | Avoid |
|---|---|---|
| Reusing transformation mechanics in pipelines | Callable logic | Treating a function as a governed metric |
| Reusing canonical rows or attributes through SQL | Queryable dataset | Embedding metric meaning only in table names |
| Reusing business meaning, KPI definitions, grain, filters, and time logic | Semantic contract | Letting dashboards redefine calculations independently |
| Serving many consumers with stable data access and operational guarantees | Queryable dataset plus dataset contract | Relying only on informal documentation |

## 3. Should the definition be domain-scoped or certified at cross-domain scope?

| Question | Suggested ownership |
|---|---|
| Is the definition meaningful only inside one domain? | Domain-owned |
| Do multiple domains need comparable numbers? | Cross-domain certified ownership through Data Governance |
| Is the definition a domain-specific variant of an enterprise definition? | Domain-owned local/shared variant with explicit pointer to enterprise certified artifact |
| Does the platform provide tooling but not business meaning? | Platform-owned mechanism, not enterprise semantic ownership |

## 4. Should this be materialized?

| Reason | Decision guidance |
|---|---|
| High reuse, high recomputation cost, stable grain | Materialization is likely justified. |
| Low reuse or exploratory logic | Keep virtual or local until reuse is proven. |
| Different consumers need different grain or freshness | Multiple materializations may be justified if named, owned, and governed. |
| Materialization duplicates a certified definition without rationale | Treat as uncontrolled duplication. |

## 5. Is duplication justified?

Duplication is acceptable only when it is intentional, visible, and owned.

| Duplication reason | Governance expectation |
|---|---|
| Domain-local scope | Name the scope and avoid presenting it as enterprise truth. |
| Performance materialization | Link to the canonical definition and document grain, refresh, and retention rationale. |
| Tool or platform constraint | Track the portability gap and owner decision. |
| Regulatory divergence | Define separate governed versions with jurisdiction or policy context. |
| Lifecycle transition | Set replacement and removal dates. |

Undocumented parallel implementations are uncontrolled duplication even when they originally had a reasonable explanation.

## 6. Is a BI-embedded semantic model enough?

| Condition | Guidance |
|---|---|
| The metric is only consumed inside one BI platform and one governed workspace. | A BI-embedded semantic layer may be enough. |
| The metric is used across BI, notebooks, APIs, apps, or multiple warehouses. | Prefer a headless or platform-level semantic contract. |
| The metric is Tier-1 or cross-domain. | Require certified semantic ownership and compatibility policy. |
| Teams bypass the BI model for custom SQL. | Add behavioral telemetry, access guidance, or a stronger semantic consumption path. |

## 7. When should enforcement become blocking?

| Signal | Enforcement response |
|---|---|
| Missing owner, FQN, lifecycle, or interface metadata for shared/certified artifacts | Block promotion. |
| Breaking change to certified artifact without version increment | Block promotion. |
| High-confidence direct duplicate of a certified artifact | Block or require explicit exception. |
| Similar but not identical logic | Advisory review; do not block automatically. |
| Local exploratory artifact | Observe only unless promoted. |

## 8. Who should own this reusable artifact?

Unclear or absent ownership is one of the most common structural causes of DRY failure. Without an explicit owner, shared artifacts degrade, compatibility goes ungoverned, and teams revert to local reimplementation.

| Artifact type | Typical owner |
|---|---|
| Shared technical utilities (merge helpers, ingestion modules, schema validators) | Platform or Data Engineering, stewarded as versioned shared packages |
| Canonical transformation logic encoding domain business rules | Domain Analytics Engineering or a central Analytics Engineering function |
| Certified cross-domain canonical datasets (Customer master, Revenue Events) | Data Governance or Data Architecture, with Analytics Engineering as implementer |
| Domain-scoped semantic models and metrics | Domain Analytics Engineering team |
| Enterprise-certified semantic contracts and cross-domain KPIs | Data Governance, requires certification gate and compatibility policy |
| CI/CD enforcement infrastructure and artifact registry | Platform or Data Engineering |

| Question | Guidance |
|---|---|
| Is this consumed by more than one domain? | Escalate to Data Governance or a cross-domain architecture body. |
| Does it encode business meaning, or only technical mechanics? | Business meaning → analytics engineering or governance ownership. Technical mechanics → platform team. |
| Who is broken by an unannounced change? | The team with the broadest consumer base is the accountability anchor and needs the strongest change governance. |
| Is there no identified owner? | A structural governance gap. Artifacts without explicit ownership cannot be safely promoted beyond `local`. |
| Is the same concept independently owned by multiple teams? | An unresolved semantic divergence. Either consolidate under one owner or explicitly govern the variants with clear scope boundaries. |

See [Article §6.1. Reuse Requires Explicit Operating Models](https://github.com/michalpru/data-platform-dry-model/blob/main/publications/article-why-reuse-breaks-at-scale.md#61-reuse-requires-explicit-operating-models) for the full operating model discussion.
