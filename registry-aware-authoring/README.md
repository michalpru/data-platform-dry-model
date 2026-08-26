# Registry-aware authoring PoC

This directory contains a proof of concept for AI-assisted, governed reuse in a data platform. It compares workspace-only authoring with registry-aware authoring for one task: compose ARPAC (Average Revenue per Active Customer) from certified reusable definitions.

## Start here

- [Article](article.md): the narrative of the problem, experiment, results, and conclusions.
- [PoC architecture](poc-architecture.md): the technical architecture, artifact catalog, scenario design, and implementation choices.
- [Demo walkthrough](demo-walkthrough.md): the prompts, recorded authoring runs, CLI output, and VS Code screenshots.
- [Results analysis](poc-results.md): the scoring rubric and per-model findings across all scenarios.

## Directory map

| Path | Scope |
|---|---|
| `article.md` | Publication-ready account of the PoC and its conclusions. |
| `poc-architecture.md` | Architecture and design reference for the PoC. |
| `demo-walkthrough.md` | Reproducible scenario walkthrough and recorded runs. |
| `poc-results.md` | Detailed results, scoring, and model-by-model analysis. |
| `scenarios/` | Self-contained input workspaces for Scenarios 1A, 1B, 1C, and 2; see its [README](scenarios/README.md). |
| `registry/` | Executable Python registry, CLI, MCP server, tests, and local registry database. |

## Scenario summary

| Scenario | What the assistant can use |
|---|---|
| 1A | Base warehouse tables only. |
| 1B | Base tables plus selected domain repositories. |
| 1C | The full codebase, including certified definitions as source. |
| 2 | The DRY Artifact Registry through CLI/MCP services and the DRY Reuse agent. |

The PoC is illustrative rather than a general benchmark. It tests whether structured governance metadata enables an AI coding assistant to select authoritative definitions and make unresolved cross-engine requirements explicit.
