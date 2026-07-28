# Recommendations & evaluation

> **Note on numbering.** The "Task 5 / Task 6" sections below come from an **earlier** review
> prompt (improve-the-use-case / anticipate-the-dbt-criticism). They are unrelated to the
> later 8-task refinement list, whose decisions are recorded in **Phase 4** immediately below.

---

## Phase 4 — refinement decisions (the 8-task list)

A later review proposed eight refinements plus a large alternative rebuild. Here is what was
adopted, what was adapted, and what was deliberately **not** done, with rationale.

### Adopted as requested

| # | Task | What changed |
|---|---|---|
| 1 | Directory per workspace | Added [`scenarios/`](scenarios/): `scenario-1a` (base warehouse tables), `scenario-1b` (+ finance & marketing domain repos), `scenario-2` (registry-aware). Each has a `workspace/`, an `expected-output/` and a README, all ANSI SQL. |
| 2 | Proper artifacts in the mocked registry | The composition artifacts were already registered; added the **retired** `finance.reporting.invoice_revenue.v1` (source contract + registered manifest) so the registry can *demonstrate rejecting a superseded artifact*. The marketing variant stays **intentionally unregistered** (domain-local) — the registry rejects it by absence. |
| 3 | Business-language service name | Renamed `ComparisonService` → `ReuseDetectionService` (`reuse_detection_service.py`). A back-compat alias/property is kept so nothing breaks. Reuse detection is framed as a *verification* step, not the entry point. |
| 4 | Whitepaper manifest vocabulary | Every registered manifest now uses **Entry Role (Producer)**, **Reuse Intent**, **Implementation Bindings**, **Dependencies**, **Ownership**, **Lifecycle**, **Interface Type**. The loader reads the new keys with fallback to the old ones, so existing manifests keep loading. |
| 5 | Search before compare | `search_artifacts` / `recommend_composition` are now the demo hero (intent-first); `compare_code` is explicitly a later verification step in the agent, prompts, README and walkthrough. |
| 6 | `recommend_composition()` | Added as a service method, an MCP tool, and a CLI `recommend` command. It resolves each named component to a registered artifact + binding in one call. |
| 7 | Rename `NEAR_MATCH` | Renamed to `STRUCTURAL_SIMILARITY` across models, classifier, prompts, agent, tests and the walkthrough ("near match" wrongly implied search). |
| 8 | ANSI SQL, dialect bindings | All authored example SQL is portable **ANSI SQL**; dialect-specific objects live only as **implementation bindings**. `recognize_revenue` now exposes Snowflake, Databricks *and* Spark bindings behind one identity, and `resolve_binding` picks the right one. |

### Deliberately **not** done — the full Snowflake artifact-rename rebuild

The same review also proposed replacing the current artifact model with a large Snowflake-based
rebuild (new artifact names, scenario-scoped `1A/1B/2` folders wired into the engine, dialect-
specific SQL throughout). This was **declined**, for reasons that reduce — not increase — the risk
of criticism:

1. **It would break a validated PoC.** The current engine, services, CLI, MCP and tests pass
   (10 passed, 1 skipped, offline). A rename-everything rebuild discards that evidence for no new
   lesson.
2. **It mixes two naming models** — the coherent existing model (`recognize_revenue`,
   `net_recognized_revenue`, `active_customer`, `revenue_events`) and the rebuild's parallel names
   (`fact_billable_events`, `invoice_revenue`, `commercial_customer_status_90d`). The proposal's
   own notes warn against exactly this double-model confusion.
3. **The valuable ideas were extracted without the rebuild.** Scenario clarity (Task 1), the
   retired-artifact rejection story (Task 2), whitepaper vocabulary (Task 4), intent-first framing
   (Task 5), `recommend_composition` (Task 6), and ANSI-SQL-plus-dialect-bindings (Task 8) were all
   adopted **on top of** the existing coherent model.

Recommended future work, if the rebuild is ever revisited: add positive relationship
classifications (`AUTHORIZED_REUSE_REFERENCE`, `NEW_COMPOSITION`) so the classifier can *affirm*
correct reuse, not only flag duplication — a smaller, additive change than a full rename.

---

# Earlier review (improve the use case & the dbt objection)

Covers **Task 5** (how to improve the use case and steps) and **Task 6** (practical value and the
likely "we already do this with dbt" criticism).

---

## Task 5 — Recommendations to strengthen the PoC

### On the use case itself

1. **Keep the asymmetry you chose.** Active-customer as a single certified contract and revenue as
   a multi-artifact composition is the right call: it exercises all three interfaces
   (callable_logic, queryable_dataset, semantic_contract) and both DRY-in-Code and DRY-in-Logic
   without becoming a toy. Resist adding a second composed metric — it adds surface without adding
   a new lesson.

2. **Make the divergence concrete, not abstract.** The scratch file diverges on a **30-day vs
   90-day** window and re-derives netting. That single, business-legible difference ("two ARPAC
   numbers on two dashboards") is more persuasive to practitioners than any structural score.
   Lead the demo with the *wrong number*, then show the tooling that would have prevented it.

3. **Show the cross-engine binding explicitly.** The strongest, least-obvious point is that
   `recognize_revenue` has a SQL-UDF binding *and* a PySpark binding under one identity. This is
   exactly the Portability-M0 failure from the whitepaper worked example (Finance rebuilt the UDF
   on another warehouse). Demo it as: "reusing the Spark binding is *not* flagged; re-deriving
   from raw tables *is*." That distinction is what a `grep`/similarity tool can never make.

4. **Add a fourth, "honest exception" mini-step.** Show the marketing 30-day metric
   (`marketing.metrics.active_customers_30d`, `lifecycle: local`) as a *legitimate* local variant
   that points to the certified one. This pre-empts the "governance = rigidity" objection and
   demonstrates *observe broadly, enforce narrowly*.

### On the registry / tooling

5. **Positioning matters more than the store.** Land the registry as a **reuse-control index /
   overlay**, not a new catalog. In this PoC that is literally true: it ingests declaration-layer
   YAML the teams already write and adds only the reuse-governance fields (lifecycle, canonical
   status, bindings, dependency edges).

6. **Prefer AST as the default signal; keep embeddings advisory.** The AST baseline caught the
   duplicate deterministically (0.66) with zero ML dependencies. Reserve the vector tier for the
   structurally-divergent reformulations AST misses, and always render its output as advisory —
   consistent with the whitepaper (embedding/LLM signals never block a build by themselves).

7. **The vector-store question, answered.** You do **not** need a hosted vector DB. Options, in
   order of simplicity, all offline:
   - **`sqlite-vec`** — a vector extension for the SQLite you already use; one file, no service.
   - **`chromadb`** in local/persistent mode — trivial API, embeds with a local
     `sentence-transformers` model (`all-MiniLM-L6-v2`, ~90 MB, downloaded once).
   - **NumPy brute-force cosine** — for a corpus this small (tens of artifacts) you don't even need
     an index; store vectors in a table and rank in memory.
   The PoC wires the embedding path as an optional, pluggable backend so none of this is required
   to run the demo.

8. **Mock Implementation Bindings the way this PoC does.** Env-normalized physical refs
   (`analytics.finance.fn_recognize_revenue` prod/uat, `finance_revenue.recognition.recognize_revenue`
   spark), each with an `attributionKey`. That is enough to demonstrate physical→logical resolution
   and to *stub* where behavioral signals would later attach — without standing up a warehouse.

9. **Add authoring-time delivery, not just a CLI.** The CLI proves the logic; the whitepaper's
   value lands at authoring time. The natural next step is a thin **MCP server** wrapping
   `resolve`/`duplicates` so Copilot/Cursor calls it live. Keep it read-only.

10. **Two things to add if you extend the PoC:** (a) a **CI gate** script that runs `duplicates`
    on changed files and posts the routed-to-review result (build-time enforcement, §4.3.2); and
    (b) a tiny **behavioral-signal stub** (a fake query-log CSV) resolved through the bindings to
    show adoption-vs-bypass — currently out of scope by design, but it is the half of the story
    the structural signals cannot tell.

### On the narrative / presentation

11. **Order the reveal by capability, not by tool.** For each pattern ask the same four questions:
    *did it find it? did it know if it's canonical? could it see beyond the workspace? could it
    tell reuse from duplication?* The side-by-side table in the walkthrough is the payload.

12. **Time-box each pattern to one command and one screenshot.** The `scan.py` output and the
    `duplicates` output are the two money shots; everything else is supporting narrative.

---

## Task 6 — Practical value and anticipated criticism

### Where the practical value is real

- **Authoring-time prevention beats post-hoc detection.** Every reviewer has approved a PR that
  quietly re-implemented an existing definition. Resolving the canonical artifact *before* code is
  written is a genuinely different economic model, and AI assistants make it cheap to deliver.
- **One logical identity across engines/dialects.** The SQL-UDF-plus-PySpark binding is a problem
  practitioners feel and current tools handle poorly. A vendor-neutral logical identity over
  physical bindings is the crisp, defensible core idea.
- **Similarity + authority, not similarity alone.** Workspace search (Copilot, Sourcegraph) gives
  similarity. The registry adds *which one is certified and who owns it* — the missing half.

### The main criticism to expect — and how to answer it

> **"We already do this. We use dbt with SQL macros and transformation models in packages, plus
> the dbt semantic layer / MetricFlow. This is solved."**

This is the objection that can get the whole idea dismissed. Answers, from strongest to weakest:

1. **dbt governs a project; the failure is cross-project and cross-engine.** dbt Mesh / `ref()` /
   package pins work beautifully *inside the dbt graph on one warehouse*. The whitepaper's failure
   modes are precisely the ones that escape it: the Finance warehouse on a **different vendor** that
   can't run the UDF, the **Spark** pipeline, the **notebook** and BI tool hitting tables directly,
   the metric replicated in a **second BI tool**. The registry's unit is a *logical identity with
   bindings across all of these*; dbt's unit is a node in one project's DAG. This PoC's
   `recognize_revenue` (UDF + PySpark) is deliberately un-representable as a single dbt node.

2. **A macro/model is not a metric; the semantic layer is not org-wide.** dbt macros give DRY in
   Code; models give DRY in Logic. Neither enforces *meaning*. MetricFlow gives DRY in Semantics —
   but only for consumers that go through it. The 30-day-vs-90-day ARPAC divergence happens the
   moment someone queries the underlying table in a notebook, which MetricFlow cannot prevent.
   The registry's job is to record *which* definition is canonical and detect the bypass — a
   governance overlay, not a second transformation tool.

3. **"Reused" and "certified" are different claims.** A dbt model existing and being `ref`-able
   does not tell you it is the *certified* definition, its lifecycle state, or who bypassed it last
   month. dbt's `unique_id` is project-scoped; there is no org-scoped, version-pinned canonical
   status, and no adoption-vs-bypass measurement. That is the reuse-control metadata the registry
   adds — and nothing else in the stack holds it.

4. **The registry is an overlay, not a replacement.** Frame it so a dbt shop hears "keep dbt; we
   index your `manifest.json`, add lifecycle/canonical status/bindings, and extend the same
   governance to your Spark and warehouse-native objects." In an operational system the manifest
   `spec` blocks are *generated* from `dbt ls --output json`, not authored by hand (the templates
   in this repo say exactly this). It is additive, which lowers the barrier to a yes.

5. **Honest scoping defuses "over-engineering."** Concede the point directly: *observe broadly,
   enforce narrowly.* Only Tier-1, cross-domain, executive/regulated definitions warrant this. For
   a single-warehouse, single-BI, all-dbt shop, the ROI is genuinely low — and you should say so.
   The value scales with heterogeneity (multi-engine, multi-BI, multi-repo), which is exactly the
   large-platform context the whitepaper targets.

### Residual weaknesses to acknowledge up front

- **Manifests can rot.** Declaration-layer YAML is only as good as the discipline maintaining it;
  generating it from tool manifests is the mitigation.
- **Structural similarity is coarse.** AST catches copy-paste and near-duplicates; it misses
  semantically-equivalent rewrites, and embeddings produce false positives on short/generic SQL.
  Both stay advisory for a reason.
- **Adoption cost is organizational, not technical.** The hard part is ownership, certification,
  and the Governance Council process — not the ~500 lines of Python here.
- **This PoC omits behavioral signals by design.** Without adoption-vs-bypass telemetry it proves
  the *authoring-time* half of the story; the runtime-bypass half is stubbed via bindings only.
