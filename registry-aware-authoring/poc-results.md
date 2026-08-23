# ARPAC Registry-Aware Authoring PoC — Results Analysis

> Analysis of the PoC runs for **Scenario 1A — Workspace-only (base tables)**,
> **Scenario 1B — Workspace-only (base tables + domain repositories)**, and
> **Scenario 2 — Registry-aware authoring** across three models
> (**GPT-5.5**, **Claude Sonnet 4.6**, **Claude Opus 4.8**), scored against the
> failure patterns catalogued in §2 and the goals in
> [demo-walkthrough.md](demo-walkthrough.md) and [README.md](README.md).

- Scope analyzed: `scenarios/<scenario>/poc-results/<model>/`
- Method: each run is checked against the failure patterns in §2; §3 links every model and
  scenario to the patterns it hit or avoided.
- Task: does **Scenario 2 — Registry-aware authoring** prevent the silent duplication that the
  workspace-only scenarios (1A/1B) produce?

---

## 1. Artifact availability per scenario

Reuse can only happen if the artifact is reachable. This table anchors every judgement below —
a model cannot be faulted for not reusing something it could not see, and the *whole point* of
Scenario 2 is that the registry makes certified, cross-engine artifacts reachable.

| Artifact | Authority / intent | 1A workspace | 1B workspace | 2 (registry + workspace) |
|---|---|:---:|:---:|:---:|
| `shared.dim_customers` (`.is_active`) | 12-month order flag — **NOT** to be reused as active def | ✓ | ✓ | ✓ |
| `shared.fact_invoices` | base table | ✓ | ✓ | ✓ |
| `shared.fact_refunds` | base table | ✓ | ✓ | ✓ |
| `finance.dim_exchange_rates` | base FX table | ✗ | ✓ | ✓ |
| `finance.invoice_revenue` | **retired** view — **NOT** to be reused | ✗ | ✓ | ✓ |
| `finance.normalize_currency` | shared FX logic | ✗ | ✓ | ✓ |
| `finance.fact_billable_events` | canonical event stream (invoices ∪ refunds) | ✗ | ✗ | ✓ |
| `finance.logic.recognize_revenue` | **certified** — **intended reuse** (numerator) | ✗ | ✗ | ✓ |
| `sales.commercial_customer_status_90d` | **certified** — **intended reuse** (denominator) | ✗ | ✗ | ✓ |
| `marketing.logic.active_customer` | domain-local login rule — **NOT** to be reused | ✗ | ✓ | ✗ |

**Key consequence:** in **1A** the correct active-customer and revenue-recognition artifacts do not
exist, so *no model can be correct* — divergence is guaranteed. In **1B** the *retired* revenue view
and the *marketing* active rule are visible while the certified ones are not, so similarity search
actively leads models toward the wrong artifacts. Only in **2** are the certified artifacts (and the
Databricks-only status view) reachable at all.

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

### Scenario 1A — base DWH tables only

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Applies revenue recognition rule (A1) — none available | ❌ none | ❌ none | ❌ none |
| Nets refunds `fact_refunds` (A2) | ✅ netted | ✅ netted | ✅ netted |
| Normalizes currency to USD (A3) | ⚠️ USD-only filter | ⚠️ USD-only filter | ⚠️ USD-only filter |
| Uses certified active-customer def (A4) — only `is_active` available | ❌ forced | ❌ forced | ❌ forced |
| Restricts numerator to active customers (C4) | ✅ | ✅ | ✅ |
| Flags the governance limitation to the reader (D) | ⚠️ partial | ✅ explicit | ⚠️ partial |

**Observation:** all three models were near-identical and actually **avoided two failure patterns** —
they netted refunds (A2) and restricted revenue to active customers (C4). But the two decisive
patterns are unavoidable here: A4 (no certified active definition exists, so `is_active` is forced)
and A1 (no recognition rule available). Sonnet partly mitigated D by explicitly warning that
`is_active` "would be replaced by a certified commercial-activity dataset" in a governed platform.

### Scenario 1B — base tables + Finance & Marketing domain repos

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Avoids retired `finance.invoice_revenue` (B1) | ❌ reused | ❌ reused | ⚠️ reused **but flagged gross** |
| Avoids Marketing `active_customer` rule (B2) | ❌ reused as "authoritative" | ❌ reused as "authoritative" | ✅ **rejected** with reasons |
| Avoids `dim_customers.is_active` (A4) | ✅ | ✅ | ✅ |
| Nets refunds `fact_refunds` (A2) | ✅ | ✅ | ✅ |
| Reuses `normalize_currency` for FX (A3) | ✅ | ⚠️ used FX table directly | ✅ |
| Recognizes authority / semantics gap (B3, B5) | ❌ no | ❌ no | ✅ partially |

**Observation:** this is the scenario that separates the models. **Sonnet and GPT fell into both
traps** — they reused the retired `invoice_revenue` *and* translated the Marketing login rule to SQL,
explicitly (and wrongly) labelling it "the authoritative active-customer definition used by executive
dashboards." That is the textbook *"duplication amplifier"* failure the PoC predicts. **Opus was
materially better**: it rejected the Marketing rule for the right reasons (marketing-login semantics,
cross-engine, missing source) and flagged that `invoice_revenue` is gross-not-net. But even Opus had
no way to reach the *certified* active definition, so it invented a substitute (POSTED-invoice
activity) — still not the governed answer. **No model can fully succeed in 1B**, confirming the PoC
thesis that similarity without authority is unsafe.

### Scenario 2 — registry-aware authoring

| Decision point (failure pattern) | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Reuses `recognize_revenue` (certified numerator) | ✅ (dbt macro binding) | ✅ (Snowflake UDF) | ✅ (Snowflake UDF) |
| Reuses `commercial_customer_status_90d` (certified denom) | ✅ | ✅ | ✅ |
| No re-derivation of revenue / refund / currency (A1–A3) | ✅ | ✅ | ✅ |
| Rejects retired `invoice_revenue` (B1) | ✅ | ✅ | ✅ |
| Avoids `dim_customers.is_active` & base-table re-derivation (A4) | ✅ | ✅ | ✅ |
| `fact_billable_events` consumed *via* `recognize_revenue`, not raw | ✅ | ✅ | ✅ |
| Confirms signatures from binding source | ✅ | ✅ | ✅ |
| Cross-engine gap flagged, no fabricated bridge (C1, C2) | ✅ references Databricks name | ⚠️ invents `SALES.DATASETS...` Snowflake name (but flags "bridge required") | ✅ references Databricks name, states "no bridge invented" |
| Restricts numerator to active customers (C4) | ✅ | ✅ | ✅ |
| Parameterized reporting date, not `CURRENT_DATE()` (C3) | ✅ | ✅ | ✅ |
| Two-layer composition (components dataset → metric) | ⚠️ merged into one SQL | ✅ | ✅ |
| Registry FQN namespace matches `enterprise.*` | ⚠️ `executive.*` | ⚠️ `finance.*` | ⚠️ `exec.*` |

**Observation:** **all three models succeeded on the substance** — every one resolved and reused the
two certified artifacts, composed only the missing ARPAC ratio, refused the retired and base-table
paths, and surfaced (never hid) the Snowflake↔Databricks binding gap. The differences are
polish-level: GPT collapsed the components dataset and metric into a single dbt model (functionally
correct, structurally thinner) and Sonnet invented a plausible Snowflake object name for the missing
binding (still flagged as required, so not silently wrong). Opus adhered most closely to the
failure-pattern guardrails, including the explicit "no bridge object is fabricated" stance (avoiding
C2). Namespace naming diverged from `enterprise.*` in all three, which is cosmetic.

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

### Decisive verdict — was the correct governed ARPAC delivered?

| Scenario | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| 1A | ❌ No | ❌ No | ❌ No |
| 1B | ❌ No | ❌ No | ❌ No |
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

### Scenario 2 — registry-aware authoring

| Governed component | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| Certified active-customer def (A4, 4) | 4 | 4 | 4 |
| Certified revenue recognition (A1, 3) | 3 | 3 | 3 |
| Refund netting (A2, 2) | 2 | 2 | 2 |
| Currency normalization (A3, 2) | 2 | 2 | 2 |
| Cross-engine composition (C1/C2, 2) | 2 | 1 | 2 |
| Active-only numerator (C4, 1) | 1 | 1 | 1 |
| Reproducible date (C3, 1) | 1 | 1 | 1 |
| **Total** | **15 / 15** | **14 / 15** | **15 / 15** |

Only the registry makes the certified inputs reachable, so every model now scores the two
high-weight components and clears the bar. Sonnet's single deduction is the fabricated Snowflake
bridge-object name (C2). Namespace and two-layer-structure differences are registry-readiness polish
(§5), not correctness, and are not scored here.

### Aggregate (normalized to 100)

| Model | 1A | 1B | 2 |
|---|:--:|:--:|:--:|
| **GPT-5.5** | 27% | 40% | 100% |
| **Sonnet 4.6** | 27% | 33% | 93% |
| **Opus 4.8** | 27% | 33% | 100% |

**The point of the matrix:** workspace-only authoring **fails for every model in both 1A and 1B**
(≤40%), no matter how much workspace context is added or how careful the model is — every
workspace-only run scores **zero on the two decisive components** (certified active definition A4 and
certified recognition A1), because those definitions are simply not reachable. The 1B totals edge
above 1A only on incidental, low-weight sub-components, never on the parts that make ARPAC correct.
Registry-aware authoring **passes for every model** (≥93%). The jump is not a model-quality effect;
it is the registry supplying the authority and cross-engine reach that no amount of workspace search
can — the PoC's core finding.

---

## 5. What worked and what did not

### What worked

- **Scenario 2 fully reproduced the intended outcome across all three models.** Every model reused
  both certified artifacts, composed only the missing ratio, and refused the retired/base-table
  paths. The registry converted a task that every workspace-only model fails (1A/1B: ≤40%) into one
  that every model passes (2: ≥93%).
- **Cross-engine surfacing worked.** All three models detected that the active-customer view is
  Databricks-only with no Snowflake binding, and none silently invented a bridge and shipped it as
  done; the gap was raised as an integration requirement.
- **Binding-source verification worked.** Every Scenario 2 run confirmed the
  `RECOGNIZE_REVENUE(P_START_DATE, P_END_DATE)` signature and the status-view columns from the actual
  source files rather than guessing — exactly the agent instruction.
- **"One identity, multiple bindings" was exercised.** GPT resolved `recognize_revenue` to its **dbt
  macro** binding while Opus/Sonnet used the **Snowflake UDF** — both correctly treated as the same
  certified capability, not duplication.
- **The 1A/1B failure modes reproduced as designed**, validating the PoC's narrative: 1A silently
  re-derives; 1B reuses the wrong-but-similar artifacts.

### What did not work / weaknesses observed

- **1B fails uniformly on correctness; only its *visibility* varies by model.** Sonnet and GPT
  reused the wrong artifacts and asserted the Marketing rule was "the authoritative active-customer
  definition"; Opus invented its own substitute instead. All three scored zero on the two decisive
  components (A4, A1) and none delivered the correct governed ARPAC — 1B is a failure for all three.
  The narrative vividness of the failure depends on the model; the failure itself does not.
- **Namespace drift in Scenario 2.** No model used the reference `enterprise.*` FQN namespace
  (`exec.*`, `executive.*`, `finance.*` instead). The prompt/agent never pins the target namespace,
  so the generated artifacts would not slot into the registry cleanly without a rename.
- **Structural variance.** GPT merged the components dataset and the metric into one dbt model,
  losing the intended two-layer composition (a reusable per-customer components
  dataset that *other* metrics could also consume).
- **Bridge-object discipline is inconsistent.** Sonnet invented a concrete Snowflake object name for
  the missing binding (flagged, but still a fabricated identifier), where the C2 guardrail is to
  reference the resolved Databricks binding and invent nothing.
- **No verification step is visible in outputs.** None of the Scenario 2 result folders contain a
  `compare_code` / verification artifact. The walkthrough presents Verify as the automatic closing
  stage; the recorded outputs do not evidence it ran.

---

## 6. Value delivered to the engineer in Scenario 2

Concretely, for the same prompt, the registry gave the engineer:

1. **Authority, not just similarity.** The engineer reused the *certified* revenue and active-customer
   definitions instead of the retired view and Marketing rule that 1B's similarity search surfaced.
   Two dashboards now compute one comparable ARPAC number.
2. **Reach beyond the workspace and across engines.** `recognize_revenue` and
   `commercial_customer_status_90d` are invisible to 1A/1B workspace search; the registry exposed
   them and resolved the correct physical binding per runtime (Snowflake UDF / dbt macro / Databricks
   view).
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

- The **1A → 1B → 2 progression is demonstrated clearly and reproducibly**: divergence (1A),
  confident wrong-reuse (1B), canonical composition (2). The registry moves a model-dependent,
  error-prone task to a near-deterministic correct one.
- The value is **uniform across models, not model-dependent**: every workspace-only run (1A and 1B,
  all three models) fails to deliver the correct governed ARPAC (≤40%), and every registry-aware run
  passes (≥93%). The registry — not model quality — is what closes the gap. That is the cleanest
  possible statement of the PoC's thesis: the limitation is the *approach*, not the model.

### Recommended changes

| Area | Issue | Recommended change |
|---|---|---|
| **Agent** | Namespace of generated artifacts drifts (`exec.*`/`executive.*`/`finance.*`) | Instruct the agent to place newly authored enterprise compositions under `enterprise.*` (or resolve the target namespace via a registry call) so outputs are registry-ready. |
| **Agent** | Bridge-object discipline inconsistent (Sonnet invented a Snowflake name) | Add an explicit rule: when `resolve_binding` returns no target-runtime binding, reference the resolved binding under its existing FQN/name and never mint a physical object identifier. |
| **Agent / Workflow** | Verify stage not evidenced in outputs | Require the agent to emit the `compare_code` verdict (e.g. a `VERIFICATION.md`) into the results folder so the closing Verify stage is auditable. |
| **Prompt** | Two-layer composition not enforced (GPT merged) | State that the components dataset and the metric are **separate reusable artifacts**, so the per-customer dataset is independently consumable. |
| **Registry methods** | Cross-engine gap is surfaced but there is no first-class "missing binding" result type | Consider a structured `resolve_binding` response field (e.g. `status: missing_target_binding`, `bound_on: [...]`) so agents handle the gap uniformly instead of prose. |
| **Registry methods** | ARPAC didn't pre-exist, so `search_artifacts` returned nothing (correct) | Optionally add a `register_artifact` path so the "safe to author, then register" step the `compare` verdict recommends can be closed in-loop. |
| **PoC framing** | Aggregate 1B % varies by incidental sub-components and can mask the uniform failure | Headline the **decisive verdict** (correct governed ARPAC delivered? No for every workspace-only run) rather than the percentage; keep the component breakdown for detail. |

**Bottom line:** the PoC achieves its goal. Scenario 2 authoring is governed, cross-engine, and
duplication-free across every model tested, and the 1A/1B baselines fail in exactly the ways the
whitepaper predicts. The remaining work is tightening the agent/prompt so the generated artifacts are
registry-ready by construction (namespace, two-layer structure, no fabricated bindings) and making the
Verify stage an explicit, recorded output.
