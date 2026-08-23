# Scenario 1C — Workspace-only (all existing codebase)

> Recorded PoC results for **Scenario 1C** across **GPT-5.5**, **Claude Sonnet 4.6**, and
> **Claude Opus 4.8**. Summarised analogically to the Scenario 1A and 1B write-ups, and scored on the
> same 15-point correctness rubric as [`../../../poc-results.md`](../../../poc-results.md).

**Workspace exposed to Copilot:** the *entire* codebase — every source file across the shared DWH,
Finance, Sales, and Marketing domains, including the certified `recognize_revenue` logic and the
certified `commercial_customer_status_90d` view definition.
**Engines:** shared DWH + Finance on **Snowflake**; Sales + Marketing on **Databricks**
(Spark SQL / PySpark) — so composing across them crosses warehouses.

This is the **optimistic** workspace-only scenario: it assumes the assistant can see *all* source
code at once — every domain repository checked out and every warehouse object materialised as SQL.
That is unlikely in practice (workspace search only sees what is open), but the PoC grants it anyway
to test whether **broad code access alone** is enough for governed reuse. It is not.

```
workspace/
├── dwh/shared/datasets/           ← dim_customers, fact_invoices, fact_refunds
├── finance-domain/finance/
│   ├── datasets/                  ← dim_exchange_rates, fact_billable_events,
│   │                                invoice_revenue (RETIRED)
│   └── logic/                     ← normalize_currency, recognize_revenue (CERTIFIED)
├── sales/datasets/
│   ├── commercial_customer_status_90d.sql   ← CERTIFIED active-customer denominator
│   └── active_customer_90d.sql              ← look-alike: POSTED-invoice-in-90d (NOT certified)
└── marketing-domain/marketing/logic/
    └── active_customer.py                   ← domain-local portal-login rule
```

## What happens

With the whole codebase visible, the models finally get the **numerator** right: all three discover
and reuse the certified `FINANCE.LOGIC.RECOGNIZE_REVENUE`, so revenue recognition, refund netting,
and currency normalization are delegated rather than re-derived. That is a genuine improvement over
1A and 1B.

The **denominator** still fails — and more instructively. Three plausible "active customer"
definitions are now visible side by side:

| Definition | Rule | Certified? |
|---|---|:--:|
| `sales.commercial_customer_status_90d` | `paid_invoice` OR `active_subscription` OR `committed_order` in 90d | ✅ the canonical one |
| `sales.active_customer_90d` | POSTED invoice in 90d | ❌ billed-customer proxy |
| `marketing.active_customer` | Marketing-Portal login in 90d | ❌ engagement proxy |

**All three models picked `active_customer_90d`** — the narrower POSTED-invoice look-alike — and
explicitly *rejected* the certified `commercial_customer_status_90d`. The reason they gave is
revealing: the certified view depends on `sales.datasets.fact_commercial_events` and
`sales.datasets.reporting_calendar`, which are **not** materialised in the workspace, so it "is not
runnable," while the look-alike reads only the always-present `shared.*` tables. **Runnability — not
authority — decided the choice.**

That is the whole point. **Nothing in the source distinguishes the certified definition from the
plausible decoy.** The certified view is *less* convenient (unresolved dependencies) and semantically
*broader* (it counts subscription-only and committed-order customers the invoice-only proxy misses),
so a model optimising for "compiles from what I can see" chooses the wrong one. The result looks
fully governed — certified numerator, clean composition, confident commentary — but silently
**understates the denominator and overstates ARPAC.**

## Result — still No

| Model | Numerator (`recognize_revenue`) | Denominator (active-customer) | Correct governed ARPAC? |
|---|:--:|:--:|:--:|
| GPT-5.5 | ✅ reused certified | ❌ `active_customer_90d` decoy | ❌ **No** |
| Claude Sonnet 4.6 | ✅ reused certified | ❌ `active_customer_90d` decoy | ❌ **No** |
| Claude Opus 4.8 | ✅ reused certified | ❌ `active_customer_90d` decoy | ❌ **No** |

Scored on the same 15-point correctness rubric as 1A/1B/2, every model lands at **≈60% and still
fails**: the numerator components (recognition A1, netting A2, currency A3) now all score, but the
single highest-weighted component — the certified active-customer definition (**A4**) — scores
**zero**, because a wrong artifact was chosen. Model-level differences are minor and offsetting:
GPT-5.5 called the Databricks `active_customer_90d` view directly from a Snowflake view (a cross-engine
defect, C1) but kept a reproducible `reporting_date`; Opus and Sonnet ported the rule inline into
Snowflake (no fabricated bridge) but anchored on `CURRENT_DATE()` (C3). None of it changes the verdict.

| Model | 1A | 1B | 1C | 2 |
|---|:--:|:--:|:--:|:--:|
| GPT-5.5 | 27% | 40% | 60% | 100% |
| Claude Sonnet 4.6 | 27% | 33% | 60% | 93% |
| Claude Opus 4.8 | 27% | 33% | 60% | 100% |

A **higher** partial score than 1B with the **same** verdict is the sharpest form of the PoC's
warning: **more visible code buys more convincing output, not a correct one.** Only the registry
(Scenario 2) carries the fact that closes the gap — *which* of the three active-customer definitions
is the certified enterprise denominator — a governance fact absent from every line of the source, no
matter how much of it is exposed.

See the per-model outputs in [`GPT-5.5/`](GPT-5.5/), [`Claude-Sonnet-4.6/`](Claude-Sonnet-4.6/), and
[`Claude-Opus-4.8/`](Claude-Opus-4.8/), and the full failure-pattern analysis in
[`../../../poc-results.md`](../../../poc-results.md).
