# Verify step — `compare_code` verdict

Closing **Verify** check for this Scenario 2 output, produced by the registry's
`ReuseDetectionService.compare_code` (the same method the MCP `compare` tool wraps), run via the
CLI against the ingested registry.

```powershell
cd registry-aware-authoring/registry
python -m dry_registry.cli compare "..\scenarios\scenario-2\poc-results\GPT-5.5\arpac_trailing_90d_components.sql" --scope registry
```

**Verdict: SAFE TO AUTHOR — no duplicate of a certified artifact.**

```
Comparison for arpac_trailing_90d_components.sql (scope=registry, method=ast):

  [INSUFFICIENT_EVIDENCE] finance.logic.recognize_revenue.v1        ast=0.11 feat=0.17 (combined=0.12) | certified
  [INSUFFICIENT_EVIDENCE] sales.datasets.commercial_customer_status_90d.v1  ast=0.09 feat=0.23 (combined=0.12) | certified
  [INSUFFICIENT_EVIDENCE] finance.logic.normalize_currency.v1       ast=0.11 feat=0.05 (combined=0.09) | shared
  [INSUFFICIENT_EVIDENCE] finance.datasets.invoice_revenue.v1       ast=0.08 feat=0.13 (combined=0.09) | retired
  [INSUFFICIENT_EVIDENCE] finance.datasets.fact_billable_events.v1  ast=0.04 feat=0.15 (combined=0.06) | certified

  No strong match found. Safe to author, but register the new artifact.
```

**Why this is the right result.** The generated component SQL *references* the certified
definitions through their registry bindings (the `recognized_revenue_relation` dbt macro and the
`commercial_customer_status_90d` view) rather than re-implementing their logic, so its structural
similarity to any single certified artifact is low by construction. That is the intended
end-state: reuse by binding, not by copy. Contrast this with the negative controls in
[`../../verification/`](../../verification/README.md), where re-derived or reformatted logic *does*
trip `PARTIAL_REIMPLEMENTATION` / `DIRECT_MATCH`.

> **Scope caveat.** This is the comparison service exercised as the Verify step and recorded here.
> It is **not** evidence that the model auto-invoked `compare_code` during the original generation
> run — wiring the agent to run and persist this verdict on every artifact is still an open step
> (see [poc-results.md](../../../poc-results.md) §5).
