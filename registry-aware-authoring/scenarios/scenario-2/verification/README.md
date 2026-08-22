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
