# PoC: Detecting code duplication in data platforms

A hands-on proof of concept for **Chapter 4 of the whitepaper** (*The Data Platform DRY Model —
Phase II: Operationalization*). It shows, on one concrete authoring task, how three levels of
tooling change whether an analytics engineer **reuses** certified definitions or **re-implements**
them.

## The authoring task

An analytics engineer must build **ARPAC = Average Revenue per Active Customer** for an
executive dashboard. Two enterprise-certified concepts already exist and should be reused:

- **Revenue** — composed from several Finance-owned artifacts (see below), on **Snowflake**.
- **Active customers** — the certified `sales.datasets.commercial_customer_status_90d.v1`
  (the `is_active_commercial_90d` definition, 90-day window), a Sales-owned dataset on **Databricks**.

## The three patterns

| # | Pattern | Tooling | Outcome |
|---|---|---|---|
| 1 | No registry, no workspace search | AI assistant on local file context only | ARPAC re-coded from raw tables; revenue rules and the activity window silently diverge |
| 2 | No registry, **with** workspace similarity search | AI assistant scans workspace repos | Similar code is found, but **authority is unknown** — is the match certified or a local copy? |
| 3 | **With** the DRY Artifact Registry | AI assistant resolves the registry at authoring time | Certified revenue + active-customer artifacts are resolved and **composed**; nothing is re-implemented |

## What the revenue side is composed of (Task 2 design)

To avoid a trivial demo, *active customers* is a single certified Sales-owned dataset on Databricks
and *revenue* is composed from artifacts across the reuse interfaces on the Snowflake stack. The
**input registry** loaded by the PoC holds **logical + dataset** artifacts only; the metric and
semantic contract are what scenario 2 *generates*:

| FQN | Interface | Kind | Lifecycle | In input registry |
|---|---|---|---|---|
| `finance.logic.recognize_revenue.v1` | callable_logic | table-valued SQL UDF **+** dbt macro (two bindings) | certified | ✓ |
| `finance.logic.normalize_reporting_currency.v1` | callable_logic | SQL macro | shared | ✓ |
| `platform.callable.dry_shared_macros.v1` (`with_boolean_flag`) | callable_logic | SQL macro | shared | ✓ |
| `finance.reporting.revenue_events.v1` | queryable_dataset | transformation model → table | certified | ✓ |
| `sales.datasets.commercial_customer_status_90d.v1` | queryable_dataset | Databricks view | certified | ✓ |
| `enterprise.datasets.customer_arpac_components_90d.v1` | queryable_dataset | composition dataset | certified | *generated (scenario 2)* |
| `enterprise.semantic.arpac_90d.v1` | semantic_contract | metric | certified | *generated (scenario 2)* |

`ARPAC = SUM(net recognized revenue for active customers) / COUNT(active customers)` — a ratio the
agent authors only once the certified inputs are resolved and composed.

## Layout

```
poc/
  README.md                     ← this file
  registry/                     ← the DRY Artifact Registry + Lookup & Compare Service
    manifests/                  ← the PoC input registry (what the engine indexes)
      registered/               ← registered DryArtifact manifests (logical + dataset)
      domains/  platform/       ← their source manifests + source code
    dry_registry/
      manifests.py              ← load registered YAML (infers binding runtime/dialect)
      store.py                  ← SQLite control plane + FTS5 search
      models.py                 ← JSON-serialisable result shapes (shared by CLI + MCP)
      comparison/               ← the ONE shared comparison core
        normalizers/            ← SQL (sqlglot) + Python (ast) normalization
        features/               ← language-neutral transformation profile
        scorers/                ← ast (token-seq), feature (Jaccard), embedding (on-demand)
        ranking.py, classification.py, engine.py
      candidate_providers/      ← registry_provider + workspace_provider (same engine)
      services/                 ← RegistryService, BindingService, ReuseDetectionService
      cli.py                    ← THIN client over the services (never uses MCP)
      mcp_server.py             ← THIN stdio MCP proxy over the services (registry scope)
    pyproject.toml              ← zero required ML deps; optional [sql] [vector] [mcp] extras
    tests/                      ← invariant tests (offline)
  workspace-similarity/
    scan.py                     ← Pattern-2 harness: a thin wrapper calling scope="workspace"
  demo/
    walkthrough.md              ← the three-pattern walkthrough with commands + real output
    arpac-authoring-scratch.sql ← the "from scratch" reimplementation (the duplicate candidate)
  scenarios/                    ← Task 1: the three workspaces Copilot "sees" (dialect-realistic fixtures)
    scenario-1a/                ← base warehouse tables only
    scenario-1b/                ← base tables + finance & marketing domain repos
    scenario-2/                 ← registry-aware (resolves the DRY Artifact Registry)
  RECOMMENDATIONS.md            ← design rationale, adopted vs. rejected refinements

.github/agents/dry-reuse.agent.md         ← Copilot custom agent (registry-aware authoring)
.github/prompts/search-registry.prompt.md ← intent-first workflow
.github/prompts/compare-with-registry.prompt.md ← code-first workflow
.vscode/mcp.json                          ← registers the local stdio MCP server
```

The PoC input registry lives in `registry/manifests/` — a curated set of **logical + dataset**
artifacts (no pre-baked metrics or semantic contracts; those are what scenario 2 generates). The
broader, generic artifact examples remain in `../dry-reference-repository/` (each top-level folder
simulates a separate team repository) and are not part of the PoC's loaded registry.

## Architecture: three responsibilities

> **Registry** knows *what exists* (start here) · the **reuse-detection service** *verifies* what
> is similar · **AI (Copilot)** knows *how to help the engineer use both*.

The CLI and the MCP server are both **thin clients** of the same application services
(`dry_registry.services`). Business logic — normalization, feature extraction, scoring,
ranking, classification — lives **once** in the shared comparison core and is reused across
scopes. Intent-first discovery (`search_artifacts` / `recommend_composition`) is the primary
path; reuse detection (`compare_code`) is a verification step. Only the *candidate source* and
the *governance metadata* differ:

- **Registry scope** — candidates are governed logical artifacts (authority, lifecycle, owner,
  reuse intent, recommended binding).
- **Workspace scope** — candidates are files in the open repos; governance is `UNKNOWN` and the
  result carries explicit coverage warnings (warehouse objects, other repos and uninstalled
  packages were not searched).

The Python services **never call an LLM**. They return structured evidence; Copilot reads that
evidence and explains/acts. The model is taught the *workflow and the tools*, never the registry
contents.

## Two ways to run it

**Scenario B — workspace, CLI only** (similarity without authority; no agent, no MCP):

```powershell
# from poc/registry
pip install -e ".[sql]"
python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql --scope workspace
# or the Pattern-2 harness:
python ../workspace-similarity/scan.py --query ../demo/arpac-authoring-scratch.sql
```

**Scenario C — registry-aware authoring through GitHub Copilot** (agent + MCP):

```powershell
# from poc/registry
pip install -e ".[sql,mcp]"          # add ,vector for the embedding tier
python -m dry_registry.cli ingest    # build the SQLite control plane once
```

Then in VS Code: reload so `.vscode/mcp.json` starts the `dry-registry` MCP server, open Copilot
Chat, pick the **DRY Reuse** agent, and use `/search-registry` (intent-first) or
`/compare-with-registry` (code-first).

## Quick start (fully offline, CLI)

```powershell
# from poc/registry
pip install -e .              # PyYAML only; add ".[sql]" for sqlglot, ".[vector]" for embeddings, ".[mcp]" for the server
python -m dry_registry.cli ingest
python -m dry_registry.cli search "recognize revenue"
python -m dry_registry.cli recommend "ARPAC" --component "net recognized revenue" --component "active customer"
python -m dry_registry.cli resolve-binding finance.logic.recognize_revenue.v1 --runtime dbt
python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql --scope registry
python -m dry_registry.cli composables "net recognized revenue" "active customer"
python -m dry_registry.cli impact finance.logic.recognize_revenue.v1
```

Add `--json` to any command to get the raw structured payload the MCP tools also return.
See [demo/walkthrough.md](demo/walkthrough.md) for the full narrative.

## Design choices

- **Fully local, zero cloud.** SQLite control plane; AST/structural similarity via the Python
  stdlib and `sqlglot`. No vector store, graph DB or remote service is required.
- **Comparison returns logical artifacts, not bindings.** An artifact with several bindings
  (a warehouse UDF *and* a dbt macro) is compared once and reported once; `resolve_binding`
  then selects the physical object for the engineer's runtime/dialect.
- **Similarity is described honestly** as "AST/parser-normalized token-sequence similarity" — not
  full semantic equivalence or tree-edit distance. Cross-language pairs (SQL vs Python) have no
  AST score and fall back to the language-neutral feature/embedding signal.
- **Embeddings are optional, advisory and on-demand.** The `[vector]` extra computes code
  embeddings per run and discards them — no vector database, no persistence. The model id is
  recorded; if the extra is absent the engine falls back to the deterministic feature signal and
  says so.
- **dbt / SQLMesh / semantic-layer are not replaced.** They are represented as implementation
  bindings on their runtimes (`runtime` = warehouse | spark | dbt | semantic, inferred from the
  registry metadata). The registry is a thin overlay that records the mapping from physical
  objects to one logical identity; it never executes anything.
