# Scenario 2 — `compare_code` verification battery

This folder holds **recorded evidence** that the DRY registry's reuse-detection service
(`compare_code`) actually fires — beyond the single "safe to author" check shown in the
[demo walkthrough](../../../demo-walkthrough.md). Each result under [`results/`](results/) is
the raw JSON payload returned by the *same* `ReuseDetectionService.compare_code` method that the
MCP `compare` tool and the CLI both call. Nothing here is hand-edited.

> **What this proves and what it does not.** These runs exercise the comparison service directly
> (via the CLI) as the closing **Verify** step, with positive *and* negative controls, and record
> the verdicts. They do **not** prove that the models auto-invoked `compare_code` during the
> original Scenario 2 generation runs — the recorded `poc-results/` folders contain only generated
> artifacts, and wiring the agent to run **and persist** this verdict with every artifact is still
> an open step (see [poc-results.md](../../../poc-results.md) §5). The evidence closes the
> *"does the detector actually work?"* gap; it does not change that honest caveat.

## What's in this folder

- **[`probes/`](probes/)** — small input files that **simulate code an engineer (or a model) just
  wrote** and wants to check against the registry before committing. Each probe is a deliberate,
  known-answer case, hand-authored from the real certified/retired sources in
  [`../workspace/`](../workspace/):
  - `probe_invoice_revenue_reimpl.sql` — a fresh reimplementation of the **retired** invoice-revenue
    rule (renamed CTEs/aliases, reformatted) → should surface the retired artifact.
  - `probe_recognize_revenue_aliased.sql` — a disguised copy of the **certified** `recognize_revenue`
    UDF (parameters/aliases renamed) → the harder "renamed copy" case.
  - `probe_recognize_revenue_reformatted.sql` — the same certified UDF with **cosmetic-only** changes
    (comments stripped, lower-cased, reflowed) → normalization should collapse it to a direct match.
  The other inputs are **not** crafted: the negative control and the positive controls are real files
  (a model-generated `scenario-1a` output, the three generated Scenario 2 outputs, and the PySpark
  `active_customer.py`), so the battery mixes synthetic probes with genuine AI output.
- **[`results/`](results/)** — the **raw `compare_code` JSON payload** for each run (similarity
  signals + governance evidence + summary), exactly as the CLI/MCP tool returns it. Each file is one
  comparison. **Which input a result belongs to is encoded in the filename** and mapped in the
  [recorded-results table](#recorded-results) below (input → scope → verdict); the payload itself
  records scope/method/matches/summary but not the query path.

Each comparison feeds **one authored file** (left side) against **the whole registry** (right side):
for every registered artifact, `compare_code` follows a **representative** binding's `source` pointer
into [`../workspace/`](../workspace/), reads that artifact's real code, fingerprints it, and scores
the authored code against it — returning similarity **plus** the artifact's lifecycle/owner/authority.
Where an artifact has several bindings, one representative source-bearing binding is chosen (preferring
the query language, then SQL), so a logical identity is compared once, not once per binding.

## How this maps to the whitepaper (§4.3.3)

The whitepaper's *Duplication Detection and Prevention Techniques* table places three build-time
signals in the CI/CD gate — **structural fingerprinting (AST)**, **embedding-based similarity**
(advisory), and **LLM-based analysis** (advisory) — all routing to review, never blocking on their
own. This PoC implements the same signal design and brings it **forward to authoring time**:

| Whitepaper §4.3.3 technique | PoC `compare_code` realization |
|---|---|
| Structural fingerprinting (AST), SQLGlot/Python AST, normalized to remove formatting & alias naming | `ast_scorer` — `sqlglot` for SQL, `ast.dump` for Python, then a difflib token-sequence ratio. Control 6b (reformat-only → `DIRECT_MATCH`) demonstrates the normalization the whitepaper describes. |
| Embedding-based similarity (advisory, model-version sensitive, re-embedding needed) | Optional `[vector]` tier, **computed on-demand per run and discarded** (no vector store), so there is nothing to invalidate on a model upgrade. Always advisory; control 7 shows graceful degradation when it is absent. |
| LLM-based analysis (advisory) | **Not** an engine scorer — the Python services never call an LLM. The DRY Reuse **agent** is the LLM consumer that reads the structured evidence and decides, keeping the deterministic signals separate from the model's reasoning. |
| Language-neutral cross-language coverage (a known gap for AST) | `feature_scorer` — a Jaccard overlap of a language-neutral transformation profile, the signal used when AST is undefined (SQL vs Python, control 5). A pragmatic PoC addition beyond the three whitepaper techniques. |
| All signals route to review, never block by themselves | The relationship label is an **advisory hint**; authority comes from the registry's lifecycle/owner fields, not the score — exactly the whitepaper's "detection routes to review" stance. |

The one structural difference: the whitepaper positions these signals at **build time** (a CI gate
after the PR is opened); the PoC runs the *same* engine at **authoring time**, and — because the CLI
and MCP server are thin clients over one shared engine — the identical check can still run as a
build-time CI gate.

### Where the fingerprint comes from (whitepaper vs. this PoC)

The scoring is fingerprint-against-fingerprint in both models; what differs is *where each side's
fingerprint lives*:

- **Whitepaper / a production build-time gate:** detection runs at build time and can score against
  **persisted derived signals** rather than re-reading every repository. The whitepaper retains
  *derived structural signals* and, for embedding-based similarity, a **stored vector corpus** keyed
  to logical identity and embedding-model version (which must be re-embedded after a model upgrade);
  it treats a vector store as needed only for advanced similarity, not as a blanket requirement, and
  does not mandate that every AST fingerprint be a persisted registry record. A typical operational
  realization persists these signals via a separate ingestion / catalog-harvesting step.
- **This PoC (compare-time):** there is **no persisted fingerprint or vector store**. At
  `compare_code` time, for each registered artifact the engine follows a **representative** binding's
  `source` pointer into [`../workspace/`](../workspace/), reads the real code, and computes its AST
  fingerprint (and any embeddings) **on the fly, then discards them**. Both sides — the candidate
  and the registered artifact — are normalized fresh on every run.

That `source:` pointer on a binding is a **PoC convenience extension**, not part of the whitepaper's
binding definition (which names the *deployed* physical object plus the attribution key, with source
reached via repository-scan connectors). The trade-off is deliberate: the PoC stays fully local and
store-free at the cost of re-reading and re-fingerprinting on each call; a production build-time gate
would typically persist the derived signals instead.

## Environment

- Python 3.10, `dry-registry` PoC package, run from `registry-aware-authoring/registry/`.
- `sqlglot` 30.12 present (SQL AST normalization). `sentence-transformers` **absent** — so the
  optional embedding tier degrades gracefully (control 7).
- Control plane: `python -m dry_registry.cli ingest` → 9 registered artifacts.

## Reproduce

```powershell
cd registry-aware-authoring/registry
python -m dry_registry.cli ingest
# example: negative control (re-derived revenue) against the registry
python -m dry_registry.cli compare "..\scenarios\scenario-1a\poc-results\GPT-5.5\arpac_trailing_90_days.sql" --scope registry
```

Add `--json` for the raw payload, `--scope workspace` for the no-governance contrast, and
`--no-embeddings` to force the deterministic structural + feature path.

## Recorded results

| # | Control | Input | Scope | Method | Top match | Lifecycle | Relationship | Combined | Outcome |
|---|---------|-------|-------|--------|-----------|-----------|--------------|---------:|---------|
| 1 | **Negative control** — revenue re-derived from raw invoices/refunds | 1A GPT-5.5 output | registry | ast | `finance.datasets.fact_billable_events.v1` | certified | `PARTIAL_REIMPLEMENTATION` | 0.20 | Detector **fires**: flags the certified billable-event rule as re-implemented (shared: `fact_invoices`, `fact_refunds`, `net`, `refund`, `revenue`); summary stays conservative on overall strength. |
| 2 | **Retired-artifact detection** — reimplemented legacy invoice revenue | `probes/probe_invoice_revenue_reimpl.sql` | registry | ast | `finance.datasets.invoice_revenue.v1` | **retired** | `PARTIAL_REIMPLEMENTATION` | 0.48 | Surfaces the **retired** artifact as the #1 match with a "do not copy" action — the exact Scenario 1B failure mode, caught. |
| 3a | **Scope contrast** — workspace | 1A GPT-5.5 output | workspace | ast | `…/finance/datasets/fact_billable_events.sql` | **UNKNOWN** | `PARTIAL_REIMPLEMENTATION` | 0.15 | Authority/lifecycle **UNKNOWN**; 5 coverage warnings ("Warehouse objects were not searched", "No governance signal…"). Action: "verify against the registry". |
| 3b | **Scope contrast** — registry | 1A GPT-5.5 output | registry | ast | `finance.datasets.fact_billable_events.v1` | certified | `PARTIAL_REIMPLEMENTATION` | 0.20 | Same input, now with `REGISTERED_CANONICAL` + `certified`/`retired` governance. This is the authority difference. |
| 5 | **Cross-language fallback** — PySpark active-customer rule | `scenario-1b/.../marketing/logic/active_customer.py` | registry | **feature** | `shared.datasets.dim_customers.v1` (and `sales.datasets.commercial_customer_status_90d.v1`) | certified | (neutral) | 0.25 | AST unsupported (Python vs SQL); engine notes the cross-language pair and falls back to the language-neutral transformation profile. No structural false precision. |
| 6 | **Normalization robustness** — alias-renamed UDF copy | `probes/probe_recognize_revenue_aliased.sql` | registry | ast | `finance.logic.recognize_revenue.v1` | certified | `PARTIAL_REIMPLEMENTATION` | 0.46 | Renamed params/aliases still rank the true certified source **#1** — a harder semantic-equivalence case. |
| 6b | **Normalization robustness** — reformat-only UDF copy | `probes/probe_recognize_revenue_reformatted.sql` | registry | ast | `finance.logic.recognize_revenue.v1` | certified | **`DIRECT_MATCH`** | 0.93 (ast 1.00) | Comments stripped, lower-cased, reflowed — normalization collapses the cosmetics to a perfect structural match. |
| 7 | **Embedding tier** — graceful degradation | `probes/probe_recognize_revenue_aliased.sql` | registry | ast | `finance.logic.recognize_revenue.v1` | certified | `PARTIAL_REIMPLEMENTATION` | 0.46 | With the `vector` extra absent, records the warning "Embeddings unavailable … used the deterministic feature-profile signal instead" and still returns a usable verdict. |
| 8a | **Positive control** — Scenario 2 GPT-5.5 | `poc-results/GPT-5.5/arpac_trailing_90d_components.sql` | registry | ast | `finance.logic.recognize_revenue.v1` | certified | `INSUFFICIENT_EVIDENCE` | 0.12 | **Safe to author**: the composition *references* certified artifacts by binding rather than copying their logic, so structural similarity is low by design. |
| 8b | **Positive control** — Scenario 2 Sonnet 4.6 | `poc-results/Claude-Sonnet-4.6/arpac_components.sql` | registry | ast | `finance.logic.recognize_revenue.v1` | certified | `PARTIAL_REIMPLEMENTATION` | 0.15 | **Safe to author** overall; a weak concept overlap is flagged advisory, not blocking. |
| 8c | **Positive control** — Scenario 2 Opus 4.8 | `poc-results/Claude-Opus-4.8/exec/reporting/arpac_active_customer_revenue_90d.sql` | registry | ast | `sales.datasets.commercial_customer_status_90d.v1` | certified | `INSUFFICIENT_EVIDENCE` | 0.19 | **Safe to author**: references certified inputs; no strong structural duplicate. |

### How to read this

- **Negative controls (1, 2, 3a, 6, 6b)** show the detector *firing* — it is not silent. A retired
  artifact and a reformatted certified UDF are both surfaced, with lifecycle attached.
- **Scope contrast (3a vs 3b)** is the core argument of the article in one input: identical code,
  but only the registry scope carries authority, lifecycle, and coverage honesty.
- **Positive controls (8a–8c)** show the complementary result: correctly *composed* Scenario 2
  outputs return "safe to author" because they reuse certified definitions by binding instead of
  copying logic — the intended end-state, verified.
- **Structural scores are deliberately conservative.** Combined similarity is a *hint*; the
  relationship label and the governance/lifecycle fields are what the agent reasons over. Low
  combined scores with a `PARTIAL_REIMPLEMENTATION` label against a `certified`/`retired` artifact
  are exactly the advisory signal the design intends.

Per-model closing-verify verdicts are also written next to each generated artifact as
`poc-results/<model>/VERIFICATION.md`.
