# Verify step — `compare_code` verdict

Closing **Verify** check for this Scenario 2 output, produced by the registry's
`ReuseDetectionService.compare_code` (the same method the MCP `compare` tool wraps), run via the
CLI against the ingested registry.

```powershell
cd registry-aware-authoring/registry
python -m dry_registry.cli compare "..\scenarios\scenario-2\poc-results\Claude-Sonnet-4.6\arpac_components.sql" --scope registry
```

**Verdict: SAFE TO AUTHOR — no strong duplicate; one advisory overlap flagged.**

```
Comparison for arpac_components.sql (scope=registry, method=ast):

  [PARTIAL_REIMPLEMENTATION] finance.logic.recognize_revenue.v1     ast=0.10 feat=0.38 (combined=0.15) | certified
  [INSUFFICIENT_EVIDENCE]    finance.datasets.fact_billable_events.v1  ast=0.11 feat=0.29 (combined=0.14) | certified
  [INSUFFICIENT_EVIDENCE]    finance.logic.normalize_currency.v1    ast=0.15 feat=0.12 (combined=0.14) | shared
  [PARTIAL_REIMPLEMENTATION] finance.datasets.invoice_revenue.v1    ast=0.08 feat=0.33 (combined=0.13) | retired
  [INSUFFICIENT_EVIDENCE]    sales.datasets.commercial_customer_status_90d.v1  ast=0.09 feat=0.23 (combined=0.12) | certified

  No strong match found. Safe to author, but register the new artifact.
```

**Why this is the right result.** The overall verdict is *safe to author* — the component SQL
reuses certified definitions by binding rather than copying them. The two advisory
`PARTIAL_REIMPLEMENTATION` labels (against the certified `recognize_revenue` and the **retired**
`invoice_revenue`) come from shared revenue/refund/netting concepts at a low combined score; they
are hints for review, not blocks. Usefully, the detector still surfaces the retired artifact so a
reviewer is reminded which revenue path must not be reused. Contrast with the negative controls in
[`../../verification/`](../../verification/README.md), where genuine re-implementations score much
higher.

> **Scope caveat.** This is the comparison service exercised as the Verify step and recorded here.
> It is **not** evidence that the model auto-invoked `compare_code` during the original generation
> run — wiring the agent to run and persist this verdict on every artifact is still an open step
> (see [poc-results.md](../../../poc-results.md) §5).
