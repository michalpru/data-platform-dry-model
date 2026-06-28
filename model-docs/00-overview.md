# Data Platform DRY Model overview

The Data Platform DRY Model describes how reuse is achieved, governed, measured, and enforced across modern data platforms. It treats DRY as an architectural property of the platform, not only as a coding convention.

This overview explains how the model docs fit together and how to use them.

## Reading order

Read the model docs in numeric order when learning the full model:

| File | Purpose |
|---|---|
| `01-glossary.md` | Defines the core vocabulary. |
| `02-platform-artifacts-and-reuse-interfaces.md` | Maps common platform artifacts to the reuse interfaces through which DRY is achieved. |
| `03-quality-attributes.md` | Defines the 13 quality attributes used to evaluate reuse capability and maturity. |
| `04-operational-maturity-assessment.md` | Turns the M0-M3 maturity definitions into an assessment method by layer and interface. |
| `05-artifact-registry-spec.md` | Defines the DRY Artifact Registry as the control plane for declared artifacts, observed objects, dependencies, and bypass signals. |
| `06-lifecycle-versioning.md` | Defines lifecycle states, identity, compatibility, versioning, and deprecation policy. |
| `07-reuse-enforcement.md` | Defines lifecycle-aware promotion gates for metadata, compatibility, duplication, and advisory similarity checks. |
| `08-adoption-metrics.md` | Defines structural and behavioral signals for reuse, bypass, attribution, and duplication hotspots. |
| `09-patterns-cookbook.md` | Captures implementation-agnostic patterns for identity, lifecycle, enterprise semantics, registry usage, CI/CD, and telemetry. |
| `10-model-elements-crosswalk.md` | Maps the model concepts to their canonical location in the repository. |
| `11-decision-guides.md` | Provides decision tables for common reuse, lifecycle, and enforcement choices. |

## How to use these docs

- Use the **glossary** and **platform artifacts/reuse interfaces** docs to establish shared language.
- Use **quality attributes** and **operational maturity** to assess current-state reuse and identify binding constraints.
- Use **lifecycle/versioning**, **registry**, and **CI/CD enforcement** to design governance mechanisms that make reuse safe and observable.
- Use **adoption metrics** to distinguish declared reuse from actual consumption behavior.
- Use the **patterns cookbook** when translating the model into concrete platform practices.

## Model boundaries

The model is tool-agnostic. It can be implemented with dbt, SQLMesh, Spark, semantic-layer tools, catalogs, CI/CD systems, or custom platform services, but it does not prescribe a vendor-specific stack.

The model is also not a replacement for data contracts, data quality tooling, metadata catalogs, or semantic layers; it applies these capabilities through a reuse-governance lens. See the whitepaper's [Model Applicability](../publications/whitepaper-data-platform-dry-model.md#model-applicability) section for how the model relates to general data-platform mechanisms.

## Known implementation risks and open questions

Most of the model builds on proven, well-understood components. A few areas need deliberate planning. Some are integration and operating-model work, and a couple are genuinely hard problems worth scoping early:

- **Identity is explicit for declared artifacts, adjudicated for observed ones.** Declared artifacts carry a stable logical identity by construction (FQN: namespace, logical name, interface type, and version), authored once and versioned. Resolving whether *observed* objects represent the same canonical concept is advisory (similarity detection only) and requires ongoing, human-in-the-loop curation. *(Model area: DRY Artifact Registry - artifact identity and similarity-based duplication detection.)*
- **Connector integration is real engineering.** The registry is conceptually a thin index, but each catalog, lineage system, and warehouse needs an ingestion adapter and identity normalization. *(Model area: DRY Artifact Registry - signal ingestion and connector adapters.)*
- **Behavioral signals depend on attribution.** Bypass detection needs service identities or workload tags that many organizations have not yet established. *(Model area: DRY Artifact Registry — observed behavioral signals; supports Reuse Measurement.)*
- **Impact analysis depends on lineage completeness.** Compatibility enforcement degrades to best-effort wherever column-level, cross-system lineage is unavailable. *(Model area: DRY Artifact Registry - declared dependencies and lineage; supports Build-Time Compatibility Enforcement.)*
- **Runtime enforcement needs a governed access path.** Warehouse permissions are table- and column-level; enforcing "certified definition only" generally requires a mediating semantic layer, governed views, or a data service API, optionally backed by access policies that deny the uncertified path. *(Model area: Runtime Enforcement - governed access path.)*
- **Certification assumes process maturity.** Approval, exception, and deprecation paths presume a functioning ownership model; lower maturity stages do not require it. *(Model area: Lifecycle and the Reuse Enforcement Model - certification, approval, exception, and deprecation.)*
- **Adoption needs migration economics.** Existing duplicated definitions are rarely replaced at once; teams need a migration path and evidence that certified reuse is cheaper than local reimplementation. *(Model area: the Staged Adoption Path - adoption and migration economics.)*

These are dependencies, not refutations: the staged adoption path delivers value before these prerequisites are fully in place.
