# Article structure (adjusted) — AI-assisted authoring for governed reuse

This is the **adjusted** scope and structure. It takes the *Proposed detailed scope and structure of
the article* from [article-prompt.md](article-prompt.md) as the baseline and records only the
changes. Where a section is unchanged, it is listed for sequence but not re-described.

**Source of truth for all claims:** [README.md](README.md), [demo-walkthrough.md](demo-walkthrough.md),
[poc-results.md](poc-results.md), and the whitepaper Chapter 4.

---

## Key changes vs. the baseline

| # | Change | Why |
|---|---|---|
| 1 | **Split "results" from "solution."** Baseline Ch.2 mixed 1A/1B failure, "what's missing," *and* the Scenario 2 answer. New Ch.3 covers only the failure (1A/1B); new Ch.4 covers the registry answer (Scenario 2). | Removes the biggest repetition risk (registry explained twice) and gives the article one clean question→answer spine. |
| 2 | **Lead with 1B, not 1A, as the headline finding.** | 1A failing is expected (answer isn't in the workspace). The non-obvious, shareable insight is that *more* context (1B) produces a more confident *wrong* answer. This is the article's unique value. |
| 3 | **Add a compact results scoreboard** (3 models × 3 scenarios, normalized %). | Converts the qualitative story into evidence in ~10 lines; strongest single persuasion asset. |
| 4 | **Add a short "why this is a fair test" note** (the zero-scoring rule for unreachable inputs). | Pre-empts the top methodological objection ("of course 1A fails"). |
| 5 | **Do not reproduce full prompts.** Show 2–3 intent bullets, link to `demo-walkthrough.md`. | Prompt itself is not the point; saves words. |
| 6 | **Frame the finding as model-independent.** | Defends against "results will be stale"; strengthens the thesis (limitation is the *approach*, not the model). |
| 7 | **Add an honest "limitations / scope" paragraph** in the conclusion (manifest rot, coarse similarity, adoption is organizational, behavioral signals out of scope). | Raises credibility with a technical-leadership audience more than an all-positive pitch. |
| 8 | **Compress "why not just dbt / semantic layer" to two points** (cross-engine logical identity; "ref-able ≠ certified"), link the rest. | Answers the top engineer objection without a digression. |
| 9 | **Subtitle sharpened** to signal "PoC" and keep the "what's missing?" hook; title kept. | Signals a real test with a finding, not a whitepaper section. |

---

## Final structure and word budget (~2,400 words target)

### 1. Intro — the ARPAC task (200–300 words)
Unchanged intent from baseline. An analytics engineer must build **ARPAC** (Average Revenue per
Active Customer) for an executive dashboard. The metric does **not** exist yet, but its composable
parts — *active customers* and *net revenue* — already exist, and in real organizations exist in
**many valid, differently-scoped definitions**. Teaser: with the workspace-only approach, **no model
delivered the correct governed metric** — and adding more code made it worse, not better.

### 2. The test: one metric, three models, three setups (150–250 words) — *new, small*
- Three setups: **1A** (base tables only), **1B** (base tables + domain repos), **2** (registry-aware).
- Three models: GPT-5.5, Claude Sonnet 4.6, Claude Opus 4.8.
- Prompt: 2–3 intent bullets only; note the exact prompt is not the point — the **failure pattern**
  is. Link to `demo-walkthrough.md`.
- **Fair-test note:** an answer that can't reach the certified input scores zero — we grade *"did you
  produce the governed ARPAC,"* not *"did you do your best with what was visible."*

### 3. Why exposing the code workspace to Copilot doesn't deliver governed reuse (700–1,000 words)
- **1A — duplication amplifier.** Models re-derive revenue recognition, refund netting, currency
  normalization from raw tables and misuse `dim_customers.is_active` (12-month flag) as the active
  definition. Runs fine, silently wrong.
- **1B — similarity without authority (headline).** With domain repos visible, models reuse the
  *retired* `invoice_revenue` view and the *Marketing* login rule, often labelling the latter
  "authoritative." More context, more confident, still wrong.
- **How models search/compare:** similarity ranking (textual/structural) with no governance signal.
- **Failure modes** (condense poc-results §2 A–D): re-derivation, wrong-but-similar reuse,
  cross-engine/composition defects, false confidence.
- **What's missing that AI can't infer from code:** authority, reuse intent/scope, lifecycle, owner,
  implementation bindings — plus **workspace-bounded coverage** (certified objects live in un-checked-out
  repos / as deployed warehouse objects).
- **The scoreboard** (normalized %). One-line takeaway: workspace-only fails for every model in 1A
  and 1B; 1B edges 1A only on incidental sub-components, never on the decisive ones.

### 4. The missing control plane: exposing the registry to Copilot (600–800 words)
- **The registry, briefly.** A logical metadata index over existing repos/warehouses that adds
  governed identity, certification, scope, ownership, lifecycle, and runtime bindings. One paragraph;
  link the whitepaper for the full concept.
- **PoC architecture** and how it maps to the whitepaper's Chapter 4 (registry service methods +
  comparison service methods → thin MCP server → **DRY Reuse** agent). Reference the architecture
  diagram.
- **Workspace search vs. registry services — pros/cons** (short table): similarity-only vs.
  similarity **plus** authority + cross-engine binding resolution.
- **The DRY Reuse agent workflow:** Business intent → Registry discovery → Reuse plan + binding
  resolution → Copilot-authored composition → Registry comparison.
- **Scenario 2 results:** all three models reused both certified artifacts, composed only the missing
  ratio, rejected the retired/base-table paths and the two registered domain-local active-customer
  look-alikes, and **flagged the Snowflake↔Databricks gap instead of fabricating a bridge**.
  Scoreboard jump to ≥93%.
- **Two-point "why not just dbt / the semantic layer"** (cross-engine identity; ref-able ≠ certified),
  link README §10 for the rest.

### 5. Conclusions (250–350 words)
- Sum up Ch.1–4 in a few sentences: reuse is an **authority** problem, not a **search** problem;
  AI answers "what looks similar," governed reuse needs "what is approved, for what scope, bound to my
  runtime."
- Reuse the "AI authoring cuts both ways" framing from the Article and Whitepaper
  (duplication amplifier ↔ reuse accelerator).
- **Model-independent** finding: the gap is the approach, not the model generation.
- **Honest limitations:** manifests can rot (generate them from tool manifests); structural similarity
  is coarse (embeddings advisory); adoption cost is organizational; behavioral/adoption telemetry is
  out of PoC scope.
- CTA: whitepaper (registry concept) + repo (`registry-aware-authoring/`).

---

## Demo / figures plan (4–5 visuals max)

| # | Placement | Visual | Purpose |
|---|---|---|---|
| 1 | Ch.2 | `registry-aware-authoring-poc-scenarios.jpg` (existing) | Artifact map: what each scenario can see. |
| 2 | Ch.3 | **Screenshot** — a 1B model output labelling the Marketing login rule "authoritative," or reusing the retired `invoice_revenue` view | The emotional peak: a confident, well-commented, *wrong* result. Most important screenshot. |
| 3 | Ch.4 | `registry-aware-authoring-poc-architecture.jpg` (existing) | How the registry/MCP/agent fit together. |
| 4 | Ch.4 | **Screenshot** — `recommend_composition` output (two `[certified]` reuses + bindings) | "Authority + binding in one call." |
| 5 | Ch.4 | **Screenshot** — `resolve_binding` returning a Databricks view *and* a dbt macro / Snowflake UDF | Proves cross-engine, one-identity-multiple-bindings — what dbt can't do. |

Keep the full command-by-command run in `demo-walkthrough.md`; link it rather than embedding it.

---

## Title and subtitle

- **Title (kept):** AI-assisted authoring for governed reuse in data platforms
- **Subtitle (sharpened):** A proof of concept implementing the DRY Artifact Registry for
  AI-assisted authoring — what context is missing, and what changes when you add it.

Alternative, higher-CTR title if a bolder framing is acceptable: *"More context made Copilot worse at
reuse."*
