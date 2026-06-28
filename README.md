# The Data Platform DRY Model

**A reference model for evaluating and operationalizing reuse in modern data platforms.**

It helps data teams and leadership identify reuse failure modes and provides the operational lens for evaluating and operationalizing reuse at scale:
- **Evaluation**: the reuse interfaces (callable logic, queryable datasets, semantic contracts), an unified evaluation framework using 13 DRY quality attributes, and operational maturity levels (M0–M3).
- **Operationalization**: the DRY Artifact Registry, CI/CD enforcement with build-time duplication detection, reuse measurement (structural and consumption-time), and a staged adoption path.

## What's in this repo:
- `model-docs/`: the core model guide. Files use a numeric prefix to give a stable reading order, from definitions to operating mechanisms. Start with Model overview: `model-docs/00-overview.md`
- `publications/`: narrative sources for the article and whitepaper: motivation, full model, adoption path, and operating model.
- `dry-reference-repository/`: a reference structure showing how to organize repositories to support reuse.
- `templates/`: tool-agnostic starting points for applying the Model in repositories, CI/CD pipelines, and artifact registries.