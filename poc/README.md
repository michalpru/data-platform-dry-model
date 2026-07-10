# PoC: Detecting code duplication in data platforms

A hands-on proof of concept for **Chapter 4 of the whitepaper** (*The Data Platform DRY Model —
Phase II: Operationalization*). It shows, on one concrete authoring task, how three levels of
tooling change whether an analytics engineer **reuses** certified definitions or **re-implements**
them.

## The authoring task

An analytics engineer must build **ARPAC = Average Revenue per Active Customer** for an
executive dashboard. Two enterprise-certified concepts already exist and should be reused:

- **Revenue** — composed from several Finance-owned artifacts (see below).
- **Active customers** — the certified `enterprise.metrics.active_customer.v1`
  (the `Is_Active_Commercial_90d` definition, 90-day window).

## The three patterns

| # | Pattern | Tooling | Outcome |
|---|---|---|---|
| 1 | No registry, no workspace search | AI assistant on local file context only | ARPAC re-coded from raw tables; revenue rules and the activity window silently diverge |
| 2 | No registry, **with** workspace similarity search | AI assistant scans workspace repos | Similar code is found, but **authority is unknown** — is the match certified or a local copy? |
| 3 | **With** the DRY Artifact Registry | AI assistant resolves the registry at authoring time | Certified revenue + active-customer artifacts are resolved and **composed**; nothing is re-implemented |

## What the revenue side is composed of (Task 2 design)

To avoid a trivial demo, *active customers* stays a single certified semantic contract and
*revenue* is composed from **four artifacts across all three reuse interfaces**:

| FQN | Interface | Kind | Lifecycle |
|---|---|---|---|
| `finance.logic.recognize_revenue.v1` | callable_logic | table-valued SQL UDF **+** PySpark function (two bindings) | certified |
| `finance.logic.normalize_reporting_currency.v1` | callable_logic | SQL macro | shared |
| `platform.callable.dry_shared_macros.v1` (`with_boolean_flag`) | callable_logic | SQL macro | shared |
| `finance.reporting.revenue_events.v1` | queryable_dataset | transformation model → table | certified |
| `finance.metrics.net_recognized_revenue.v1` | semantic_contract | metric | certified |

`ARPAC = net_recognized_revenue / active_customer` — a ratio metric composing two certified
metrics (`finance.metrics.arpac.v1`).

## Layout

```
poc/
  README.md                     ← this file
  registry/                     ← the DRY Artifact Registry engine (Task 4)
    dry_registry/               ← Python package: manifests, SQLite store, AST fingerprint,
                                   pluggable similarity backends, CLI
    pyproject.toml              ← zero required ML deps; optional [sql] and [vector] extras
  workspace-similarity/
    scan.py                     ← Pattern 2 harness (AST baseline; embeddings pluggable)
  demo/
    walkthrough.md              ← the three-pattern walkthrough with commands + real output
    arpac-authoring-scratch.sql ← the "from scratch" reimplementation (the duplicate candidate)
  RECOMMENDATIONS.md            ← Task 5 (improvements) + Task 6 (evaluation & the dbt objection)
```

The artifacts themselves live in `../dry-reference-repository/` (each top-level folder simulates
a separate team repository).

## Quick start (fully offline)

```powershell
# from poc/registry
pip install -e .              # PyYAML only; add ".[sql]" for sqlglot, ".[vector]" for embeddings
python -m dry_registry.cli ingest
python -m dry_registry.cli resolve revenue
python -m dry_registry.cli duplicates ../demo/arpac-authoring-scratch.sql --interface callable_logic --lang sql
python -m dry_registry.cli impact finance.logic.recognize_revenue.v1
```

See [demo/walkthrough.md](demo/walkthrough.md) for the full three-pattern narrative.

## Design choices

- **Fully local, zero cloud.** SQLite control plane; AST/structural similarity via the Python
  stdlib and `sqlglot`. No vector store is *required*.
- **Vector store is optional and offline.** The `[vector]` extra adds a local
  `sentence-transformers` model for semantic similarity — no API keys, no network at query time.
- **Implementation Bindings are mocked** as env-normalized physical refs (warehouse tables/UDFs,
  package symbols, semantic-layer metric ids). The registry never executes anything; it only
  records the mapping from physical objects to one logical identity.
