# ARPAC Registry-Aware Authoring PoC — Results Analysis

> Analysis of the PoC runs for **Scenario 1A — Workspace-only (base tables)**,
> **Scenario 1B — Workspace-only (base tables + domain repositories)**,
> **Scenario 1C — Workspace-only (all existing codebase)**, and **Scenario 2 — Registry-aware
> authoring** across three models
> (**GPT-5.5**, **Claude Sonnet 4.6**, **Claude Opus 4.8**), scored against the
> failure patterns catalogued in §2 and the goals in
> [demo-walkthrough.md](demo-walkthrough.md) and [poc-architecture.md](poc-architecture.md).

- Scope analyzed: `scenarios/<scenario>/poc-results/<model>/`
- Method: each run is checked against the failure patterns in §2; §3 links every model and
  scenario to the patterns it hit or avoided.
- Task: does **Scenario 2 — Registry-aware authoring** prevent the silent duplication and
  wrong-artifact selection that the workspace-only scenarios (1A/1B/1C) produce?

---

## 1. Artifact availability per scenario

Reuse can only happen if the artifact is reachable. This table anchors every judgement below —
a model cannot be faulted for not reusing something it could not see, and the *whole point* of
Scenario 2 is that the registry makes certified, cross-engine artifacts reachable.

| Artifact | Authority / intent | 1A workspace | 1B workspace | 1C workspace | 2 (registry + workspace) |
|---|---|:---:|:---:|:---:|:---:|
| `shared.dim_customers` (`.is_active`) | 12-month order flag — **NOT** to be reused as active def | ✓ | ✓ | ✓ | ✓ |
| `shared.fact_invoices` | base table | ✓ | ✓ | ✓ | ✓ |
| `shared.fact_refunds` | base table | ✓ | ✓ | ✓ | ✓ |
| `finance.dim_exchange_rates` | base FX table | ✗ | ✓ | ✓ | ✓ |
| `finance.invoice_revenue` | **retired** view — **NOT** to be reused | ✗ | ✓ | ✓ | ✓ |
| `finance.normalize_currency` | shared FX logic | ✗ | ✓ | ✓ | ✓ |
| `finance.fact_billable_events` | canonical event stream (invoices ∪ refunds) | ✗ | ✗ | ✓ | ✓ |
| `finance.logic.recognize_revenue` | **certified** — **intended reuse** (numerator) | ✗ | ✗ | ✓ | ✓ |
| `sales.commercial_customer_status_90d` | **certified** — **intended reuse** (denominator) | ✗ | ✗ | ✓ | ✓ |
| `sales.active_customer_90d` | Sales billed-customer proxy — **NOT** to be reused | ✗ | ✗ | ✓ | ✓ |
| `marketing.logic.active_customer` | domain-local login rule — **NOT** to be reused | ✗ | ✓ | ✓ | ✓ |

**Key consequence:** in **1A** the correct active-customer and revenue-recognition artifacts do not
exist, so *no model can be correct* — divergence is guaranteed. In **1B** the *retired* revenue view
and the *marketing* active rule are visible while the certified ones are not, so similarity search
actively leads models toward the wrong artifacts. In **1C** both certified artifacts become visible,
but the Sales invoice-only look-alike does too: code availability improves the numerator outcome but
still supplies no authority signal for the denominator. Only in **2** does the registry make that
authority explicit and resolve the artifacts' runtime bindings. Both domain-local look-alikes
(`sales.active_customer_90d`, `marketing.logic.active_customer`) are themselves registered as
`domain_canonical`, so in **2** the registry *surfaces* them as **discoverable-and-rejected** —
like the retired `invoice_revenue` — rather than hiding them; the executive request still resolves
only to the enterprise-wide certified denominator.

### The active-customer definition trap

The denominator is where every workspace-only scenario breaks, because "active customer" has several
legitimate, co-existing definitions — and nothing in the code says which one is the governed
denominator for a revenue metric:

| Domain | Artifact | Local definition of "active" | Legitimate purpose | Why it's wrong for ARPAC |
|---|---|---|---|---|
| Marketing | `active_customer.py` | Logged into the Marketing Portal in 90d | Campaign reach, engagement analytics | Engagement ≠ revenue; excludes paying customers who never log in |
| Sales | `active_customer_90d.sql` | Has a **POSTED invoice** in 90d | Sales-ops / AR dashboards, billed-account tracking | Billing activity ≠ full commercial activity |
| Enterprise (certified) | `commercial_customer_status_90d.sql` | `paid_invoice` **OR** `active_subscription` **OR** `committed_order` in 90d | Governed denominator for revenue metrics | — (this is the canonical one) |

In **1B** the Marketing rule is the visible decoy; in **1C** the Sales `active_customer_90d`
look-alike joins it, and every model picks it over the certified view because the certified one's
dependencies are not materialized in the workspace (so it "does not run") while the look-alike reads
the always-present `shared.*` tables. Only the registry marks `commercial_customer_status_90d` as the
certified enterprise denominator — the distinction that separates the correct ARPAC from a
plausible-but-wrong one. Full Scenario 1C write-up:
[`scenarios/scenario-1c/poc-results/README.md`](scenarios/scenario-1c/poc-results/README.md).

---

## 2. Failure patterns AI models can make

This catalogue enumerates the ways an AI assistant silently produces a wrong-but-plausible ARPAC —
the failure surface every run was checked against (not split by scenario). Each pattern is a *silent*
defect: the SQL runs and looks correct, so nothing downstream flags it. §3 links each pattern to what
every model actually did per scenario.

**A. Re-deriving governed logic from raw base tables ("duplication amplifier").**
When no authoritative definition is discoverable, the model authors the metric from first principles
and re-implements rules it should have reused:

- **A1 — Revenue recognition skipped.** Sums raw `POSTED` invoice amounts instead of applying the
  certified recognition rule (`finance.logic.recognize_revenue`).
- **A2 — Refunds / credit notes ignored.** `fact_refunds` is never netted, so revenue is overstated
  (netting belongs inside `fact_billable_events` → `recognize_revenue`).
- **A3 — Currency normalization ignored.** Mixed-currency amounts are summed as if all USD because no
  FX table is visible (`finance.logic.normalize_currency` is the owner).
- **A4 — Wrong active-customer definition.** `dim_customers.is_active` (a 12-month order flag) is used
  instead of the certified 90-day commercial-activity status
  (`sales.datasets.commercial_customer_status_90d`). This is the least structurally-visible yet most
  consequential error.

**B. Reusing similar-but-wrong artifacts ("reuse without governance").**
When similar code *is* discoverable, similarity ranking has no authority signal, so the model reuses
artifacts that look right but are not:

- **B1 — Reusing a retired artifact.** `finance.datasets.invoice_revenue` is a *retired* view that
  skips refunds and is invoice-date based; nothing in the workspace states it is retired.
- **B2 — Reusing a domain-local definition as enterprise.** The Marketing login-based
  `marketing.logic.active_customer` rule is adopted (often asserted as "authoritative") though it is
  a marketing-portal-login definition, not the certified enterprise commercial-activity one.
- **B3 — No authority signal.** Ranking is by resemblance; certified/retired/domain-local are
  indistinguishable to workspace search.
- **B4 — Workspace-bounded blindness.** Certified artifacts that exist only as deployed warehouse
  objects or in un-checked-out repos (the `recognize_revenue` UDF, the certified status view) are
  invisible, so they can never be found.
- **B5 — Similarity ≠ semantics.** Consequential divergences (net-vs-gross revenue,
  enterprise-vs-marketing active) barely register structurally, so they pass unnoticed.

**C. Cross-engine and composition defects.**
Even a model that finds the right artifacts can compose them wrongly:

- **C1 — Cross-engine blindness / brittle bridge.** The revenue view (Snowflake) and the
  active-customer rule (Databricks) live on different engines; joining them silently assumes a
  brittle cross-warehouse export that nothing flags.
- **C2 — Fabricating a bridge object.** When `resolve_binding` returns no target-runtime binding, the
  model invents a physical object name and presents the gap as solved, instead of flagging
  provisioning as an integration requirement.
- **C3 — Non-reproducible reporting date.** Anchoring on `CURRENT_DATE()` instead of a parameter
  (`:as_of_date`) makes point-in-time executive snapshots (month-end packs) non-reproducible.
- **C4 — Numerator not restricted to the denominator population.** Counting revenue from non-active
  customers in the numerator while dividing by the active-customer count yields a metric that is not
  ARPAC.

**D. False confidence (the meta-pattern).** Across A–C, the model presents a confident, well-commented
result with no governance caveat. Reuse without authority can be *worse* than authoring from scratch
because it lends false credibility to retired or domain-local code — and no pipeline fails.

Where these patterns showed up in the actual runs is detailed in §5 (What worked and what did not) and
scored in §4.

---

## 3. What each model did (reuse-decision matrix)

Legend: ✅ pattern avoided / correct outcome · ⚠️ defensible-but-flawed · ❌ failure pattern hit ·
`n/a` not reachable in this scenario. Codes in parentheses map to the failure patterns in §2.

These are evidence-based diagnostic matrices, not the scoring rubric: their rows record decisions
observable in each run, so row counts vary. Scenario 1C has the same source artifacts as Scenario 2;
what it lacks is the registry's explicit authority, lifecycle, and runtime-binding metadata. The
fixed seven-component rubric used to score every scenario appears in §4.

### Scenario 1A — base DWH tables only

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Applies revenue recognition rule (A1) — none available | ❌ none | ❌ none | ❌ none |
| Nets refunds `fact_refunds` (A2) | ✅ netted | ✅ netted | ✅ netted |
| Normalizes currency to USD (A3) | ⚠️ USD-only filter | ⚠️ USD-only filter | ⚠️ USD-only filter |
| Uses certified active-customer def (A4) — only `is_active` available | ❌ asserted as executive-aligned | ❌ reused as dashboard-aligned | ❌ asserted as governed/dashboard-aligned |
| Restricts numerator to active customers (C4) | ✅ | ✅ | ✅ |
| Flags the governance limitation to the reader (D) | ❌ asserted as executive-aligned | ❌ asserted as dashboard-aligned | ❌ asserted as governed/dashboard-aligned |

**Observation:** all three models were near-identical and actually **avoided two failure patterns** —
they netted refunds (A2) and restricted revenue to active customers (C4). But the two decisive
patterns cannot be resolved here: A4 (no certified active definition is available) and A1 (no
recognition rule is available). None of the models mitigated D: each used `is_active` directly and
presented it as suitable for executive reporting despite the absence of a certified
commercial-activity definition.

### Scenario 1B — base tables + Finance & Marketing domain repos

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Avoids retired `finance.invoice_revenue` (B1) | ❌ reused | ❌ reused | ⚠️ reused **but flagged gross** |
| Avoids Marketing `active_customer` rule (B2) | ❌ reused as "authoritative" | ❌ reused as "authoritative" | ✅ **rejected** with reasons |
| Avoids `dim_customers.is_active` (A4) | ✅ | ✅ | ✅ |
| Nets refunds `fact_refunds` (A2) | ✅ | ✅ | ✅ |
| Reuses `normalize_currency` for FX (A3) | ✅ | ⚠️ used FX table directly | ✅ |
| Recognizes authority / semantics gap (B3, B5) | ❌ no | ❌ no | ⚠️ partially |

**Observation:** this is the scenario that separates the models. **Sonnet and GPT fell into both
traps** — they reused the retired `invoice_revenue` *and* translated the Marketing login rule to SQL,
explicitly (and wrongly) labelling it "the authoritative active-customer definition used by executive
dashboards." That is the textbook *"duplication amplifier"* failure the PoC predicts. **Opus was
materially better**: it rejected the Marketing rule for the right reasons (marketing-login semantics,
cross-engine, missing source) and flagged that `invoice_revenue` is gross-not-net. But even Opus had
no way to reach the *certified* active definition, so it invented a substitute (POSTED-invoice
activity) — still not the governed answer. **No model can fully succeed in 1B**, confirming the PoC
thesis that similarity without authority is unsafe.

### Scenario 1C — all existing codebase

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Reuses `recognize_revenue` (certified numerator) | ✅ | ✅ | ✅ |
| Reuses `commercial_customer_status_90d` (certified denominator) | ❌ chose `active_customer_90d` | ❌ chose `active_customer_90d` | ❌ chose `active_customer_90d` |
| No re-derivation of revenue / refund / currency (A1–A3) | ✅ | ✅ | ✅ |
| Avoids Sales billed-customer proxy (B2/B3) | ❌ | ❌ | ❌ |
| Handles the Snowflake ↔ Databricks boundary (C1/C2) | ❌ direct cross-engine reference | ✅ logic port, no bridge | ✅ logic port, no bridge |
| Restricts numerator to active customers (C4) | ✅ | ✅ | ✅ |
| Parameterized reporting date, not `CURRENT_DATE()` (C3) | ✅ | ❌ | ❌ |

**Observation:** exposing all source code produces a material but incomplete improvement. Every model
reuses the certified numerator; every model nevertheless chooses the Sales `active_customer_90d`
look-alike over the certified `commercial_customer_status_90d`. The certified view's unresolved Sales
dependencies make it less convenient, while the look-alike is executable from `shared.*` tables. This
is not a failure of retrieval: both candidates were retrieved. It is a failure of authority — no
source file identifies which definition is the certified executive denominator.

### Scenario 2 — registry-aware authoring

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Reuses `recognize_revenue` (certified numerator) | ✅ (Snowflake UDF) | ✅ (Snowflake UDF) | ✅ (Snowflake UDF) |
| Reuses `commercial_customer_status_90d` (certified denom) | ✅ | ✅ | ✅ |
| No re-derivation of revenue / refund / currency (A1–A3) | ✅ | ✅ | ✅ |
| Rejects retired `invoice_revenue` (B1) | ✅ | ✅ | ✅ |
| Rejects both registered domain-local active definitions | ✅ non-selected | ✅ non-selected | ✅ explicit |
| Avoids `dim_customers.is_active` & base-table re-derivation (A4) | ✅ | ✅ | ✅ |
| `fact_billable_events` consumed *via* `recognize_revenue`, not raw | ✅ | ✅ | ✅ |
| Confirms signatures from binding source | ✅ | ✅ | ✅ |
| Cross-engine gap flagged, no fabricated bridge (C1, C2) | ✅ references Databricks name | ✅ flags "bridge required"; provisional `SALES.DATASETS...` name noted, not shipped | ✅ references Databricks name, states "no bridge invented" |
| Restricts numerator to active customers (C4) | ✅ | ✅ | ✅ |
| Reproducible reporting date, not `CURRENT_DATE()` (C3) | ✅ reporting-date grain | ❌ `CURRENT_DATE()` | ❌ `CURRENT_DATE()` |
| Separate components dataset → metric | ✅ aggregate components | ✅ per-customer components | ✅ aggregate components |
| Registry FQN namespace matches `enterprise.*` | ⚠️ `executive.*` | ⚠️ `exec.*` | ⚠️ `executive.*` |

**Observation:** this rerun adds a harder governance test: both the Sales billed proxy and the
Marketing login proxy are now registered and discoverable as `domain_canonical`. All three models
still select only the certified enterprise denominator. The explicit `Target runtime is Snowflake SQL
warehouse` prompt constraint resolves revenue to its registered Snowflake UDF binding, so the outputs
are raw Snowflake SQL rather than dbt artifacts. Sonnet names a provisional Snowflake identifier for
the missing Sales binding but explicitly flags it as a required bridge rather than shipping a silent
cross-engine join; GPT and Opus reference the Databricks binding directly. Opus and Sonnet also use
`CURRENT_DATE()`, which makes historical executive snapshots non-reproducible.

---

## 4. Scoring matrix

The rubric scores **one thing: did the model deliver the correct, governed ARPAC?** Every governed
component the correct answer requires is scored identically in all three scenarios. Crucially,
**input availability is NOT factored in**: if a model cannot produce a component because the
certified input was unreachable, that scores **zero** — exactly like getting it wrong. The inability
of the workspace-only setups (1A/1B) to reach the certified inputs is not an excuse; it is precisely
the deficiency the registry exists to remove. A solution that is not the correct governed ARPAC is a
failure, full stop.

### Correctness rubric (the governed ARPAC), max 15

| Governed component (failure pattern) | Weight |
|---|:--:|
| Certified active-customer definition — `commercial_customer_status_90d` (A4) | 4 |
| Certified revenue recognition — `recognize_revenue` (A1) | 3 |
| Refund / credit-note netting (A2) | 2 |
| Currency normalization to USD (A3) | 2 |
| Cross-engine composition handled, no fabricated bridge (C1/C2) | 2 |
| Active-only numerator (C4) | 1 |
| Reproducible parameterized reporting date (C3) | 1 |

Every scenario is scored on this **same** set of attributes. Using a *wrong* artifact for a component
— `dim_customers.is_active` or the Marketing rule for the active-customer definition (A4), or the
retired `invoice_revenue` for recognition (A1) — scores **0** on that component, exactly like not
producing it at all. There are **no negative penalties**, so totals are directly comparable across
scenarios: `is_active` in 1A and the Marketing rule in 1B are both simply a zero on A4.

Because each component is scored independently and there are no penalties, a run keeps the points for
the components it gets right — which is why the workspace-only setups land at partial scores rather
than 0%, and only an all-correct run reaches 15/15 (100%).

### Decisive verdict — was the correct governed ARPAC delivered?

| Scenario | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| 1A | ❌ No | ❌ No | ❌ No |
| 1B | ❌ No | ❌ No | ❌ No |
| 1C | ❌ No | ❌ No | ❌ No |
| 2 | ✅ Yes | ✅ Yes | ✅ Yes |

### Scenario 1A — workspace, base tables only

| Governed component | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Certified active-customer def (A4, 4) | 0 | 0 | 0 |
| Certified revenue recognition (A1, 3) | 0 | 0 | 0 |
| Refund netting (A2, 2) | 2 | 2 | 2 |
| Currency normalization (A3, 2) | 1 | 1 | 1 |
| Cross-engine composition (C1/C2, 2) | 0 | 0 | 0 |
| Active-only numerator (C4, 1) | 1 | 1 | 1 |
| Reproducible date (C3, 1) | 0 | 0 | 0 |
| **Total** | **4 / 15** | **4 / 15** | **4 / 15** |

The certified active definition and recognition rule are not in the workspace, so all three models
score zero on the two highest-weighted components — and therefore fail, by construction. Refund
netting is the only governed rule they reconstruct correctly.

### Scenario 1B — workspace, base + Finance & Marketing repos

| Governed component | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Certified active-customer def (A4, 4) | 0 | 0 | 0 |
| Certified revenue recognition (A1, 3) | 0 | 0 | 0 |
| Refund netting (A2, 2) | 2 | 2 | 2 |
| Currency normalization (A3, 2) | 2 | 1 | 2 |
| Cross-engine composition (C1/C2, 2) | 0 | 0 | 0 |
| Active-only numerator (C4, 1) | 1 | 1 | 1 |
| Reproducible date (C3, 1) | 1 | 1 | 0 |
| **Total** | **6 / 15** | **5 / 15** | **5 / 15** |

The extra repos buy no *decisive* correctness: the certified inputs are still absent, so A4 and A1 —
the two highest-weighted components — stay at zero for every model, and the verdict is still No. The
small bump over 1A comes only from incidental sub-components (reusing the FX function, parameterizing
the date), not from getting ARPAC right. If anything 1B is the more dangerous failure: the output
looks more complete while still resting on the retired revenue view and a non-enterprise
active-customer rule.

### Scenario 1C — workspace, all existing codebase

| Governed component | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Certified active-customer def (A4, 4) | 0 | 0 | 0 |
| Certified revenue recognition (A1, 3) | 3 | 3 | 3 |
| Refund netting (A2, 2) | 2 | 2 | 2 |
| Currency normalization (A3, 2) | 2 | 2 | 2 |
| Cross-engine composition (C1/C2, 2) | 0 | 2 | 2 |
| Active-only numerator (C4, 1) | 1 | 1 | 1 |
| Reproducible date (C3, 1) | 1 | 0 | 0 |
| **Total** | **9 / 15** | **10 / 15** | **10 / 15** |

All three models now score the numerator components because `recognize_revenue` is visible and reused.
All three score zero on the highest-weighted component because they select the Sales invoice-only
look-alike rather than the certified commercial-status definition. GPT also receives no cross-engine
points for referencing the Databricks view directly from Snowflake; Sonnet and Opus port the rule,
which avoids that unsupported join but does not make the selected denominator governed.

### Scenario 2 — registry-aware authoring

| Governed component | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Certified active-customer def (A4, 4) | 4 | 4 | 4 |
| Certified revenue recognition (A1, 3) | 3 | 3 | 3 |
| Refund netting (A2, 2) | 2 | 2 | 2 |
| Currency normalization (A3, 2) | 2 | 2 | 2 |
| Cross-engine composition (C1/C2, 2) | 2 | 2 | 2 |
| Active-only numerator (C4, 1) | 1 | 1 | 1 |
| Reproducible date (C3, 1) | 1 | 0 | 0 |
| **Total** | **15 / 15** | **14 / 15** | **14 / 15** |

The registry makes the certified inputs' authority and runtime bindings explicit, so every model now
scores the two high-weight components and clears the bar. Sonnet and Opus each lose only the date-reproducibility
point (C3, `CURRENT_DATE()`); Sonnet flags the missing Snowflake binding as a required bridge rather
than shipping a silent cross-engine join, so it keeps full cross-engine credit (C2).
Namespace and components-grain differences are registry-readiness polish, not correctness, and are
not scored here.

**Decisive verdict: all three models deliver the correct governed ARPAC and reject both registered
decoys; the two 93% scores differ from GPT's 100% only on the reproducible reporting-date point (C3).**

### Aggregate (normalized to 100)

| Model | 1A | 1B | 1C | 2 |
|---|:--:|:--:|:--:|:--:|
| **GPT-5.5** | 27% | 40% | 60% | 100% |
| **Sonnet 4.6** | 27% | 33% | 67% | 93% |
| **Opus 4.8** | 27% | 33% | 67% | 93% |

**The point of the matrix:** workspace-only authoring **fails for every model in 1A, 1B, and 1C**
(≤67%). More workspace context produces real partial improvement: in 1C all models reuse the
certified recognition rule. But every workspace-only run still scores **zero on the decisive
active-customer component** (A4), because code does not declare which visible candidate is the
certified enterprise denominator. Registry-aware authoring **passes for every model** (≥93%). The
gap is not a model-quality effect; it is the registry supplying governed authority and cross-engine
binding information that workspace search alone cannot supply.

---

## 5. What worked and what did not

### What worked

- **Scenario 2 fully reproduced the intended outcome across all three models.** Every model reused
  both certified artifacts, composed only the missing ratio, and refused the retired/base-table
  paths. The registry converted a task that every workspace-only model fails (1A/1B/1C: ≤67%) into one
  that every model passes (2: ≥93%). The rerun strengthened that result by surfacing two registered
  domain-local active-customer alternatives without selecting either one.
- **Cross-engine surfacing worked.** All three models detected that the active-customer view is
  Databricks-only with no Snowflake binding, and none silently invented a bridge and shipped it as
  done; the gap was raised as an integration requirement.
- **Binding-source verification worked.** Every Scenario 2 run confirmed the
  `RECOGNIZE_REVENUE(P_START_DATE, P_END_DATE)` signature and the status-view columns from the actual
  source files rather than guessing — exactly the agent instruction.
- **Runtime-aware binding resolution was exercised.** The explicit Snowflake warehouse target caused
  all three models to use the registered `FINANCE.LOGIC.RECOGNIZE_REVENUE` UDF binding. The registry
  still records the dbt macro as an alternate binding of that same certified identity; it was not the
  runtime requested by this rerun.
- **The 1A/1B/1C failure modes reproduced as designed**, validating the PoC's narrative: 1A silently
  re-derives; 1B reuses the wrong-but-similar artifacts; 1C reaches the right numerator but still
  selects a wrong denominator without an authority signal.

### What did not work / weaknesses observed

- **1B and 1C fail uniformly on governed correctness; only their partial scores vary by model.** In
  1C, all models reuse `recognize_revenue` but choose the Sales invoice-only look-alike for the
  denominator. In 1B, Sonnet and GPT
  reused the wrong artifacts and asserted the Marketing rule was "the authoritative active-customer
  definition"; Opus invented its own substitute instead. All three scored zero on the two decisive
  components (A4, A1) and none delivered the correct governed ARPAC — 1B is a failure for all three.
  The narrative vividness of the failure depends on the model; the failure itself does not.
- **Namespace drift in Scenario 2.** No model used the reference `enterprise.*` FQN namespace
  (`exec.*`, `executive.*`, `finance.*` instead). The prompt/agent never pins the target namespace,
  so the generated artifacts would not slot into the registry cleanly without a rename.
- **Components-grain variance.** Sonnet authors a reusable per-customer components dataset, while
  GPT and Opus aggregate their components outputs to reporting-date grain. Both preserve the governed
  ARPAC formula, but the per-customer shape is the more reusable layer.
- **Bridge-object naming is a readiness nit.** Sonnet flagged the missing binding as a required
  bridge — satisfying the C2 guardrail, since nothing was silently shipped — but still minted a
  provisional Snowflake object name; the cleaner practice is to reference the resolved Databricks
  binding under its existing name and mint no physical identifier.
- **The automatic Verify stage is still not visible in outputs.** The new components SQL files were
  independently checked through the CLI and received safe-to-author summaries, but none of the agent
  result folders contains a `compare_code` artifact. The walkthrough presents Verify as the automatic
  closing stage; the recorded agent outputs do not evidence it ran.

---

## 6. Value delivered to the engineer in Scenario 2

Concretely, for the same prompt, the registry gave the engineer:

1. **Authority, not just similarity.** The engineer reused the *certified* revenue and active-customer
   definitions instead of the retired view and Marketing rule that 1B's similarity search surfaced.
   Two dashboards now compute one comparable ARPAC number.
2. **Authority and binding resolution beyond code search.** `recognize_revenue` and
  `commercial_customer_status_90d` are invisible to 1A/1B workspace search; in 1C they are visible,
  but the registry is still what identifies the correct definition and resolves its physical binding
  per runtime (Snowflake UDF / dbt macro / Databricks view).
3. **A shrunk authoring surface.** The engineer wrote only the ARPAC ratio (and a thin components
   join) instead of re-deriving revenue recognition, refund netting, currency normalization and the
   activity window — four governed rules avoided.
4. **An honest integration signal.** Rather than a plausible-but-wrong cross-engine join, the engineer
   received an explicit "no Snowflake binding exists; provision one" requirement — a real risk raised
   at authoring time, not in production.
5. **Provenance for free.** The generated metric manifests carry `reuses:` provenance back to the
   certified FQNs, making the lineage auditable.

---

## 7. Are the results satisfying? Do they reflect the registry's value?

**Yes — the results are satisfying and do reflect the value of the DRY Artifact Registry**, with
caveats worth acting on.

- The **1A → 1B → 1C → 2 progression is demonstrated clearly and reproducibly**: divergence (1A),
  confident wrong-reuse (1B), partial improvement but a wrong denominator (1C), canonical
  composition (2). The registry moves a model-dependent, error-prone task to a near-deterministic
  correct one.
- The value is **uniform across models, not model-dependent**: every workspace-only run (1A, 1B,
  and 1C, all three models) fails to deliver the correct governed ARPAC (≤67%), and every
  registry-aware run passes (≥93%). The registry — not model quality — is what closes the gap.

### Recommended changes

| Area | Issue | Recommended change |
|---|---|---|
| **Agent** | Namespace of generated artifacts drifts (`exec.*`/`executive.*`/`finance.*`) | Instruct the agent to place newly authored enterprise compositions under `enterprise.*` (or resolve the target namespace via a registry call) so outputs are registry-ready. |
| **Agent** | Bridge-object naming (Sonnet flagged the bridge as required but still minted a provisional Snowflake name) | Add an explicit rule: when `resolve_binding` returns no target-runtime binding, reference the resolved binding under its existing FQN/name and never mint a physical object identifier. |
| **Agent / Workflow** | Verify stage not evidenced in outputs | Require the agent to emit the `compare_code` verdict (e.g. a `VERIFICATION.md`) into the results folder so the closing Verify stage is auditable. |
| **Prompt** | Two-layer composition not enforced (GPT merged) | State that the components dataset and the metric are **separate reusable artifacts**, so the per-customer dataset is independently consumable. |
| **Registry methods** | Cross-engine gap is surfaced but there is no first-class "missing binding" result type | Consider a structured `resolve_binding` response field (e.g. `status: missing_target_binding`, `bound_on: [...]`) so agents handle the gap uniformly instead of prose. |
| **Registry methods** | ARPAC didn't pre-exist, so `search_artifacts` returned nothing (correct) | Optionally add a `register_artifact` path so the "safe to author, then register" step the `compare` verdict recommends can be closed in-loop. |
| **PoC framing** | Partial scores improve from 1A through 1C but can mask the uniform failure | Headline the **decisive verdict** (correct governed ARPAC delivered? No for every workspace-only run) rather than the percentage; keep the component breakdown for detail. |

**Bottom line:** the PoC achieves its goal. Scenario 2 authoring is governed, cross-engine, and
duplication-free across every model tested, and the 1A/1B/1C baselines fail in exactly the ways the
whitepaper predicts. The remaining work is tightening the agent/prompt so the generated artifacts are
registry-ready by construction (namespace, two-layer structure, no fabricated bindings) and making the
Verify stage an explicit, recorded output.
