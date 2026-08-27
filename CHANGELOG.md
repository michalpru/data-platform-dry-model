# Changelog

Releases follow [Semantic Versioning](https://semver.org/) and are tagged on `main`.


## [1.1.0] - 2026-06-28

Adds the Registry-aware authoring PoC, demonstrating how the DRY Artifact Registry helps an AI coding assistant to become a reuse accelerator

### Added

- Adds the Registry-aware authoring PoC, including recorded runs for GPT-5.5, Claude Sonnet 4.6, and Claude Opus 4.8.
- Adds the Registry implementation, YAML manifests, SQLite-derived index, service APIs, MCP interface, CLI, comparison-based duplication detection, and the DRY Reuse agent workflow.
- Compares four authoring setups:
  - IDE workspace code only: Scenarios 1A, 1B, and 1C
  - DRY Artifact Registry exposed to the assistant: Scenario 2
- Documents the observed result: code availability alone improves partial correctness but does not establish artifact authority; Registry-aware authoring selects certified artifacts and surfaces missing runtime bindings.
- Adds PoC architecture, walkthrough, scoring rubric, scenario results, and publication material.

[1.1.0]: https://github.com/michalpru/data-platform-dry-model/releases/tag/v1.1.0


## [1.0.1] - 2026-07-03

Publishes the *The Data Platform DRY Model* whitepaper as a formatted website. 
No changes to the substance of the Model.

### Added

- GitHub Pages site — the whitepaper is now published as a formatted,
browsable site at
michalpru.github.io/data-platform-dry-model.
- Deployment workflow — added a GitHub Actions workflow that renders the
Quarto site and deploys it to GitHub Pages on every push to main. Actions
are pinned to commit SHAs for supply-chain hardening, with Dependabot
maintaining the pins.

[1.0.1]: https://github.com/michalpru/data-platform-dry-model/releases/tag/v1.0.1


## [1.0.0] - 2026-06-28

First complete public edition of the Data Platform DRY Model.

### Added

- Model guide (`model-docs/`): concepts, quality attributes, lifecycle, artifact registry, CI/CD enforcement, adoption metrics, patterns cookbook, decision guides, and the Operational Maturity assessment.
- Publications (`publications/`): the whitepaper *The Data Platform DRY Model* and the companion article *Why Reuse Breaks at Scale in Data Platforms*.
- Code examples (`code-examples/`) illustrating DRY patterns across the code, logic, and semantic layers.
- DRY reference repository structure (`dry-reference-repository/`).
- Reusable declaration templates (`templates/`).

[1.0.0]: https://github.com/michalpru/data-platform-dry-model/releases/tag/v1.0.0
