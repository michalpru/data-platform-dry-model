# Verify step — `compare_code` verdict

Closing **Verify** check for this Scenario 2 output, produced by the registry's
`ReuseDetectionService.compare_code` (the same method the MCP `compare` tool wraps), run via the
CLI against the ingested registry.

```powershell
cd registry-aware-authoring/registry
python -m dry_registry.cli compare "..\scenarios\scenario-2\poc-results\Claude-Opus-4.8\exec\reporting\arpac_active_customer_revenue_90d.sql" --scope registry
```

**Verdict: SAFE TO AUTHOR — no duplicate of a certified artifact.**

```
Comparison for arpac_active_customer_revenue_90d.sql (scope=registry, method=ast):

  [INSUFFICIENT_EVIDENCE]    sales.datasets.commercial_customer_status_90d.v1  ast=0.17 feat=0.26 (combined=0.19) | certified
  [INSUFFICIENT_EVIDENCE]    finance.logic.normalize_currency.v1    ast=0.20 feat=0.08 (combined=0.17) | shared
  [PARTIAL_REIMPLEMENTATION] finance.logic.recognize_revenue.v1     ast=0.12 feat=0.31 (combined=0.16) | certified
  [INSUFFICIENT_EVIDENCE]    finance.datasets.invoice_revenue.v1    ast=0.13 feat=0.24 (combined=0.16) | retired
  [INSUFFICIENT_EVIDENCE]    finance.datasets.fact_billable_events.v1  ast=0.11 feat=0.23 (combined=0.13) | certified

  No strong match found. Safe to author, but register the new artifact.
```

**Why this is the right result.** The generated reporting dataset *references* the certified
active-customer and revenue definitions through their registry bindings rather than
re-implementing them, so structural similarity to any single certified artifact stays low. The one
advisory `PARTIAL_REIMPLEMENTATION` hint against certified `recognize_revenue` reflects shared
revenue/netting vocabulary at a low combined score — a review hint, not a block. Contrast with the
negative controls in [`../../verification/`](../../verification/README.md), where genuine
re-implementations of the certified or retired logic score materially higher.

> **Scope caveat.** This is the comparison service exercised as the Verify step and recorded here.
> It is **not** evidence that the model auto-invoked `compare_code` during the original generation
> run — wiring the agent to run and persist this verdict on every artifact is still an open step
> (see [poc-results.md](../../../poc-results.md) §5).
