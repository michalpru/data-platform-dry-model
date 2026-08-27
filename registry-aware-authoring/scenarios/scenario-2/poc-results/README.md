# Scenario 2 — Registry-aware authoring results

> Recorded rerun results for **Scenario 2** across **GPT-5.5**, **Claude Sonnet 4.6**, and
> **Claude Opus 4.8**. The runs use the **DRY Reuse** agent, the re-ingested registry, and the
> explicit target runtime **Snowflake SQL warehouse**.

## Rerun condition

The registry contained **11 artifacts** for this rerun. In addition to the certified ARPAC inputs,
it exposed two registered, domain-scoped active-customer alternatives:

- `sales.datasets.active_customer_90d.v1` — Sales billed-customer proxy (POSTED invoice only).
- `marketing.logic.active_customer.v1` — Marketing Portal login proxy.

The request was still for an executive ARPAC, so the agent had to select the enterprise canonical
rather than either domain-local look-alike.

## Result — the registry-aware path passes

**Decisive verdict: correct governed ARPAC — Yes for all three models; both registered domain-local decoys rejected.** The two 93% scores (Sonnet, Opus) differ from GPT's 100% only on the reproducible reporting-date point (C3).

| Model | Certified numerator | Certified denominator | Domain-local alternatives | Snowflake binding gap | Score | Correct governed ARPAC? |
|---|---|---|---|---|:---:|:---:|
| GPT-5.5 | `finance.logic.recognize_revenue.v1` UDF | `sales.datasets.commercial_customer_status_90d.v1` | Non-selected | Flagged; no bridge invented | 15 / 15 | Yes |
| Claude Sonnet 4.6 | `finance.logic.recognize_revenue.v1` UDF | `sales.datasets.commercial_customer_status_90d.v1` | Non-selected | Flagged as required bridge; provisional name noted, not shipped | 14 / 15 | Yes |
| Claude Opus 4.8 | `finance.logic.recognize_revenue.v1` UDF | `sales.datasets.commercial_customer_status_90d.v1` | Explicitly rejected | Flagged; no bridge invented | 14 / 15 | Yes |

All three models produced Snowflake SQL rather than dbt artifacts. Every output delegates
recognition, refund netting, and USD normalization to the certified `recognize_revenue` UDF; it
uses the certified commercial-status view for the active-customer population; and it limits revenue
to that population.

This is stronger evidence than the earlier Scenario 2 run: the registry now makes the two plausible,
registered domain-local alternatives discoverable, yet the executive request still resolves to the
enterprise canonical.

## What the outputs show

- **Authority beats similarity.** The workspace-only runs selected `active_customer_90d` or the
  Marketing login definition because those definitions were convenient or similar. Here the registry
  supplies `reuseIntent`, lifecycle, ownership, and implementation bindings, so the agent selects
  `commercial_customer_status_90d` for an executive request.
- **Runtime is a real input.** The prompt's Snowflake warehouse target resolves revenue to
  `FINANCE.LOGIC.RECOGNIZE_REVENUE`; the same logical artifact also has a registered dbt binding,
  but that was not the runtime requested by this run.
- **The registry reports an integration requirement instead of hiding it.** The certified
  active-customer artifact has only a Databricks binding. GPT and Opus keep that condition explicit
  without inventing a Snowflake bridge. Sonnet also flags the missing binding as a required bridge
  rather than shipping a silent cross-engine join, though it names a provisional Snowflake object.

## Scoring notes

The 15-point rubric is defined in [`../../../poc-results.md`](../../../poc-results.md).

- GPT earns the full score: it keeps reporting-date grain instead of anchoring the metric to
  `CURRENT_DATE()` and does not fabricate the missing binding.
- Sonnet loses one point for anchoring the output to `CURRENT_DATE()` rather than a reproducible
  as-of date; it keeps full cross-engine credit because it flags the missing binding as a required
  bridge rather than shipping a silent join.
- Opus loses one point for anchoring the output to `CURRENT_DATE()`.

Artifact namespace and output-shape variation are registry-readiness concerns, but not deductions
under the governed-ARPAC correctness rubric. In particular, GPT's components output is
reporting-date-grain while Sonnet's is per-customer; both preserve the governed numerator and
denominator, but the latter is the more reusable components shape.

## Verification status

A post-run registry-scope `compare_code` check over each components SQL file returned the overall
verdict **safe to author**. Sonnet also produced advisory feature-overlap warnings against revenue
artifacts because its explanatory comments repeat invoice, refund, and currency concepts; the
service still returned a safe top-level summary. These were CLI validation checks performed after
generation, not artifacts emitted by the DRY Reuse agent, so the agent's automatic Verify stage is
still not evidenced by the rerun folders.

## Deliverables

- [GPT-5.5](GPT-5.5/) — components SQL, metric SQL, and metric manifest.
- [Claude Sonnet 4.6](Claude-Sonnet-4.6/) — components SQL/contract, metric SQL/manifest, and
  semantic model.
- [Claude Opus 4.8](Claude-Opus-4.8/) — components SQL/contract and metric SQL/manifest.

For the cross-scenario comparison and detailed rubric, see
[`../../../poc-results.md`](../../../poc-results.md). For the executable workflow, see
[`../README.md`](../README.md) and [`../../../demo-walkthrough.md`](../../../demo-walkthrough.md).
