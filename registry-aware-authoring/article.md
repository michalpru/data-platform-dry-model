# AI-assisted authoring for governed reuse in data platforms

*A proof of concept implementing the DRY Artifact Registry for AI-assisted authoring — what context is missing, and what changes when you add it.*

*Version 0.1 (draft) · August 2026*

---

## An analytics engineer is asked for one number

An analytics engineer is handed a familiar task: build **ARPAC — Average Revenue per Active Customer** (trailing 90 days) for an executive dashboard. 
They open their IDE, describe the metric to an AI coding assistant — GitHub Copilot in this PoC — and let it draft the SQL.

ARPAC does not exist yet as a governed metric. But its parts do. **Net recognized revenue** and **active customers** are among the most reused concepts in any company — defined and redefined across warehouses, notebooks, and BI tools. In most large organizations, each concept has several *valid but different* definitions. Some are legitimate but intentionally scoped to a team or domain, such as Marketing or Finance, rather than approved as company-wide canonicals. Others are legacy or retired tables, views, or code that remain in repositories and can be mistaken for valid reuse candidates by an AI coding assistant.

So the real task is not "write ARPAC from scratch." It is "compose ARPAC for executive reporting **from definitions already approved as company-wide canonicals**." That is a reuse problem, and it is exactly where AI-assisted authoring is supposed to help.

This article reports a small proof of concept that tested how well it does. The result is the interesting part: when the AI coding assistant could use only the code available in its workspace, **none of the models produced the correct governed metric** — even when that workspace contained the *entire* codebase. More code improved partial correctness, but it neither identified the governed definition the metric required nor resolved the missing runtime binding for it.

---

## The test: one metric, three models, four setups
The diagram below maps the ARPAC use case across the enterprise data platform, highlighting the two certified enterprise definitions that the governed metric should reuse.
![Data Landscape In The PoC](../publications/assets-diagrams/registry-aware-authoring-poc-scenarios.jpg)

The PoC runs the same ARPAC task through four authoring setups and three current models — **GPT-5.5**, **Claude Sonnet 4.6**, and **Claude Opus 4.8**:

| Authoring setup | Scenario | What the AI coding assistant can use |
|---|---|---|
| **Workspace-only (base tables)** | **Scenario 1A** | The shared warehouse base tables: `dim_customers`, `fact_invoices`, and `fact_refunds` |
| **Workspace-only (base tables + domain repositories)** | **Scenario 1B** | The base tables plus chosen Finance and Marketing domain code, so the assistant can find similar existing logic |
| **Workspace-only (all existing codebase)** | **Scenario 1C** | The *entire* codebase across every domain — including the certified recognition logic and active-customer definition as source — the most optimistic workspace assumption |
| **Registry-aware authoring** | **Scenario 2** | The **DRY Artifact Registry**, exposed as structured tools over a thin MCP server and driven by the custom **DRY Reuse agent** |

The prompt is the same business intent in every run: "I need a trailing-90-day ARPAC metric for executive reporting...
- Numerator = net recognized revenue in USD, over the trailing 90 days, counting *only* active customers
- Denominator = the count of active customers using the definition used in other executive dashboards... 
Reuse existing definitions, datasets, or functions where appropriate, and explain what was reused"

Full prompts and recorded runs are documented in [demo walkthrough](demo-walkthrough.md). Each scenario's repositories are mocked and deliberately scoped, so the test isolates *which context the assistant can reach*.

**One deliberately harsh grading question** decides each run: *did it deliver the correct, governed ARPAC?* If a needed composable artifact was unreachable, that component scores **zero**, exactly like getting it wrong. The workspace-only scenarios withhold direct warehouse and catalog access (an MCP tool for either could close that reachability gap); the test asks whether the governance facts needed to select and bind the correct definition are available.

---

## Why exposing the code workspace to AI Coding Asssitant doesn't deliver governed reuse

### Scenario 1A — Workspace-only (base tables): the duplication amplifier

This is the baseline. With only base tables visible and nothing reusable to find, every model builds ARPAC from first principles — summing raw invoice amounts, netting refunds by hand, and reaching for `dim_customers.is_active` (a 12-month order flag, not the certified customer status). The SQL runs and looks correct, yet it silently re-implements three governed rules (billable-event assembly, revenue recognition, currency normalization) and uses the wrong active-customer definition. Nothing fails; two dashboards now show two different ARPAC numbers. This is the *duplication amplifier* — the failure the later scenarios build on.

### Scenario 1B — Workspace-only (base tables + domain repositories): similarity without authority

The obvious fix is to give the AI coding assistant more to work with, so Scenario 1B adds some artifacts (functions and datasets) from the domain repositories. This is where the result becomes counter-intuitive, and where the article's headline sits: **more context did not fix the answer — it made the wrong one more convincing.**

With domain code visible, the models found similar artifacts and reused them — the wrong ones:

- The Finance repo contains `invoice_revenue` — a **retired** view that skips refunds. Nothing in the code repository says "retired," so models reused it and reproduced a known defect
- The Marketing repo contains a login-based active-customer rule — a **domain-local** definition never certified as enterprise-level canonical. Two of the three models translated it to SQL and explicitly labelled it *"the authoritative active-customer definition used by executive dashboards."*
- Meanwhile the actually-certified recognition function and the certified active-customer status view were **invisible to workspace search** because they exist only as deployed warehouse objects and in repositories that were never checked out. A direct warehouse or catalog MCP tool could expose them; that tool was intentionally outside this workspace-only setup.

### Scenario 1C — Workspace-only (all existing codebase): reachable but not distinguishable

Scenario 1C grants the **most optimistic** workspace assumption possible: the assistant can see the *entire* codebase at once — every domain repository checked out and every warehouse object exposed as source, including the certified `recognize_revenue` logic and the certified `commercial_customer_status_90d` definition. This is **less probable** in practice — assuming an assistant has, and searches, every relevant repository and every deployed object across every domain is not realistic — but the PoC grants it anyway to test the strongest possible version of "just give the AI more code." Even under this optimistic assumption, it still does not compose the metric correctly.

With the whole codebase visible, all three models finally get the **numerator** right — they discover and reuse the certified `recognize_revenue`, so revenue recognition, refund netting, and currency normalization are delegated rather than re-derived. But the **denominator** fails again, and more instructively: three plausible "active customer" definitions are now visible side by side — the certified `commercial_customer_status_90d` (paid invoice *or* active subscription *or* committed order), a Sales `active_customer_90d` look-alike (POSTED invoice only), and the Marketing login rule. **Every model chose the look-alike** and explicitly rejected the certified view — because the certified definition depends on Sales tables that are not materialized in the workspace and therefore "does not run," while the look-alike reads the always-present shared tables. Runnability decided the answer; **authority never entered into it**, because nothing in the source encodes it.

The output looks *more* trustworthy than 1A or 1B — a certified numerator, a clean composition, confident commentary — while silently using the wrong denominator, understating the active-customer count and overstating ARPAC. More visible code bought more convincing output, not a correct one.

### The failure modes, in one place
Across the runs, the workspace-only setups fail in four recurring ways — each one *silent*, because the SQL is valid:

- **Re-deriving governed logic** from raw tables (recognition, refund netting, currency, activity window).
- **Reusing similar-but-wrong artifacts** — a retired view, or a domain-local rule promoted to "enterprise."
- **Cross-engine and composition defects** — joining a Snowflake view to a Databricks rule as if a bridge existed.
- **False confidence** — a well-commented result presented with no governance caveat.

### What AI cannot infer from code alone
Even when an AI coding assistant can search the exposed domain code, workspace search ranks matches only by textual and structural similarity. The decisive information is **not in the source**. Even with perfect search over every repository, an assistant cannot read off:

- **Authority** — is this the certified definition, or one of five look-alikes?
- **Reuse intent and scope** — was this built to be reused enterprise-wide, within one domain, or never?
- **Lifecycle** — is it shared, certified, deprecated, or retired?
- **Ownership** — who is accountable for it, and can approve a change?
- **Implementation bindings** — even if the right logic is found, how is it consumed from *this* engineer's runtime and dialect?

And there is a coverage limit on top of the semantic one: **workspace search only sees what is open.** Assuming an assistant will have, and will search every relevant repository and every deployed warehouse object across every domain is not realistic. Widening the workspace does not resolve this; it just adds more places a retired, local, or irrelevant artifact can be picked up with false confidence.

AI-assisted authoring makes it cheap to *write* code and to *find* something that looks reusable. It does not answer the question the task actually turns on: **what should be reused.** That answer requires governance context that spans the repositories — and does not live in any of them.

### The scoreboard

Scored on the single question — *did it deliver the correct governed ARPAC?* — the workspace-only setups fail for every model:

| Model | 1A (base tables) | 1B (base tables + selected domain repos) | 1C (all existing codebase) | 2 (registry-aware) |
|---|:--:|:--:|:--:|:--:|
| **GPT-5.5** | 27% | 40% | 60% | 100% |
| **Claude Sonnet 4.6** | 27% | 33% | 67% | 93% |
| **Claude Opus 4.8** | 27% | 33% | 67% | 93% |

Each percentage is the run's score on a 15-point rubric — points awarded across the governed components (recognition, refund netting, currency, activity window, the certified active-customer definition, and correct composition/binding) — expressed as a fraction of the 15 available.

The verdict for every workspace-only run — all three models across 1A, 1B, and 1C — is the same: **no, the governed ARPAC was not delivered.** The climb from 1A (27%) to 1B (33–40%) to 1C (60–67%) is meaningful partial progress: in 1C every model reaches the certified recognition rule for the numerator. But every model still misses the decisive denominator fact — *which* of the visible active-customer definitions is the certified one. Even with the entire codebase in view, that authority is not in the code, so 1C scores higher and still fails. (Full rubric and per-component scores: [poc-results.md](poc-results.md); Scenario 1C detail: [scenarios/scenario-1c/poc-results/README.md](scenarios/scenario-1c/poc-results/README.md).)

These results are **use-case-specific**, not precise predictions for every metric or codebase. A different mix of visible artifacts could produce better or worse workspace-only results. The PoC instead shows a repeated tendency: when several plausible definitions exist, code access alone does not establish which one is authoritative or how to consume it in the target runtime.

---

## The governance control plane: exposing the registry to AI coding assistant

### What the registry is

The turning point in the PoC is a small **DRY Artifact Registry** — the concept introduced in the [whitepaper](https://michalpru.github.io/data-platform-dry-model/). It is not a new warehouse or catalog. It is a thin **reuse-governance metadata** layer over the repositories, warehouses, and catalogs that already exist, adding only the facts they do not hold: a stable logical identity per artifact, its lifecycle state, reuse intent and scope, owner, and its **implementation bindings** — the physical objects (a warehouse UDF, a dbt macro, a Databricks table/view) that realise the same logical definition across engines and dialects. As the whitepaper describes, it stores manifests for the three reuse interfaces — **callable logic, queryable datasets, and semantic contracts** — as a vendor-neutral reuse architecture. It stores metadata and pointers; it never stores or executes code.

The registry is **not** a code- or data-distribution mechanism and never sits in the query-execution path; its lookup runs over *governance metadata*, not a corpus of source. Where workspace similarity answers *"what looks like this,"* the registry answers what the task turns on: *which definition is authoritative, for what scope, and how do I bind to it from my runtime.* That also answers *"isn't this just RAG?"* A retrieval system could index registry records, but retrieval alone cannot certify an artifact, choose its runtime binding, or hold anyone accountable for it.

Warehouse- and catalog-backed MCP servers can expose deployed objects, schemas, lineage, and whatever governance metadata their connected systems maintain. They may therefore close the **reachability** gap in Scenarios 1A and 1B, and could provide this capability if they consistently expose the same governed metadata. This PoC does not compare those tools. The registry instead acts as an integration layer: it combines source-control declarations with repository, warehouse, catalog, and lineage signals into one normalized reuse-governance view. That avoids requiring every source system to carry the full metadata set or relying on the AI to infer authority and bindings from disparate signals.

### What was implemented in the PoC

The PoC exposes the registry to the assistant as a thin, layered stack that maps directly onto Chapter 4 of the whitepaper:

![PoC architecture: registry services and comparison services, a thin MCP server, and the DRY Reuse agent](../publications/assets-diagrams/registry-aware-authoring-poc-architecture.jpg)

- **The registry** — a local SQLite control plane built from pure-YAML artifact manifests. It holds logical identities, authority, bindings, and dependency edges; each binding points to real code in the workspace but the registry holds none of it.
- **Registry service methods** — intent-first discovery and binding resolution: `search_artifacts`, `find_composable_artifacts`, `recommend_composition`, `resolve_binding`.
- **Comparison service methods** — code-first verification: `compare_code` fingerprints authored code with a shared AST/feature engine and returns similarity **plus** governance evidence.
- **A thin MCP server** — exposes both service groups as structured tools; it holds no business logic.
- **The DRY Reuse agent** — a custom Copilot agent whose instructions drive the workflow and read each resolved binding's source to confirm columns and signatures before referencing them.

Notably, the Python services **never call an LLM**. They return structured evidence; the agent reads that evidence and acts. The determinism lives in the tools; the language understanding lives in the model.

### Workspace search vs. registry services

Both approaches find candidates. Only one of them carries the governed authority — which definition is certified, for what scope, who owns it, and how to bind to it.

| | Workspace similarity search | Registry-backed resolution |
|---|---|---|
| **Finds** | Structurally/textually similar code | The governed artifact for the intent |
| **Coverage** | Only repositories open in the workspace | Every registered artifact, across engines |
| **Authority signal** | None — lifecycle/owner/scope unknown | Certified vs. retired vs. domain-local, with owner |
| **Runtime fit** | Raw file; consumer resolves it | `resolve_binding` returns the object for the runtime/dialect |
| **Failure mode** | Confident reuse of the wrong artifact | Flags gaps (e.g. missing cross-engine binding) instead of guessing |

Workspace search reduces accidental re-implementation. Registry-backed resolution makes reuse of the *canonical* artifact the path of lowest friction — and refuses to fake what it cannot resolve.

### The agent workflow

The DRY Reuse agent turns the prompt into a governed sequence — **Business intent → Registry discovery → Reuse plan and binding resolution → Copilot-authored composition → Registry comparison.** Its system instructions enforce the discipline: search the registry before implementing; look for a complete artifact first, then composable parts; resolve bindings before generating code; never fabricate a cross-engine bridge; confirm interface contracts from source, not memory; and compare the authored code back against the registry when done.

For ARPAC, discovery finds no existing metric, so the agent decomposes the formula into its two named components and calls `recommend_composition`, which resolves each to its **enterprise-wide certified** definition and its binding — the domain-local `fact_billable_events` and the raw `dim_customers` flag are deliberately *not* selected for an executive metric.

### Checking code that already exists

Discovery is intent-first, but the registry also works **code-first**. When an engineer has already written a transformation and wants to know whether something similar already exists, `compare_code` takes that code, normalizes it into an AST and a language-neutral feature profile, and scores it against the registered artifacts. It returns not just a similarity signal — with an optional, advisory **embedding** comparison to catch structurally-divergent rewrites the AST baseline would miss — but the **governance evidence** behind each match: which artifact it resembles, its lifecycle and owner, and a recommended action. Similarity is a candidate; authority still comes from the registry, not from the score. One scoring difference is by design: a production build-time gate would typically score against *persisted* derived signals in the registry — normalized AST fingerprints, and for embedding similarity a stored vector corpus — whereas this PoC persists none, reading each registered artifact's source (via a representative binding's `source` pointer) from the workspace and computing the AST fingerprint and any embeddings on the fly, then discarding them (a demo convenience, not a production design). These are the whitepaper's build-time duplication-detection signals (§4.3.3 — AST structural fingerprinting plus advisory embeddings) brought forward to authoring time; a recorded [verification battery](scenarios/scenario-2/verification/) with positive and negative controls confirms the detector both fires on real duplication and stays quiet on correctly-composed reuse.

The same call is the agent's closing **Verify** step by design: find composables first, author only the missing part, then compare the result back so it cannot silently re-implement a governed artifact. In these PoC runs that check was exercised directly through the CLI over the generated SQL — it returns *no strong match, safe to author*, because the revenue, netting, currency and activity-window rules are referenced, not re-derived. A recorded [verification battery](scenarios/scenario-2/verification/) backs this with positive *and* negative controls: re-derived revenue trips `PARTIAL_REIMPLEMENTATION` against the certified billable-event rule, a reimplemented legacy view surfaces the **retired** `invoice_revenue` artifact, a reformatted copy of the certified UDF scores a `DIRECT_MATCH` through normalization, and the three governed Scenario 2 outputs each return *safe to author* — so the detector demonstrably fires, not just stays quiet. Wiring the agent to run and persist that verdict with every generated artifact — rather than exercising it via the CLI — is a still-open step, not something the recorded generation runs prove.

Because the MCP server and the CLI are thin clients over the **same** Lookup & Compare services, an engineer does not need the agent to use them: `search`, `recommend`, `resolve-binding`, and `compare` are callable from the command line for an ad-hoc check at authoring time, or as a build-time CI gate so the same comparison fires before merge.

### Scenario 2 — Registry-aware authoring: results

**Decisive verdict: correct governed ARPAC — Yes for all three models; both registered decoys rejected.** The outcome held across all three models. Every one:

- reused the certified `recognize_revenue` (numerator) and `commercial_customer_status_90d` (denominator), authoring **only** the missing ARPAC ratio;
- rejected the retired `invoice_revenue` view and the base-table re-derivation that 1A/1B fell into;
- rejected the two newly registered domain-local look-alikes — the Sales billed proxy and the Marketing login proxy — while retaining the certified enterprise denominator;
- resolved the registered Snowflake UDF binding for revenue and the Databricks view binding for active status, so the certified definitions were referenced rather than re-implemented;
- and, when the active-customer status resolved only to Databricks while the target engine was Snowflake, surfaced the missing binding as an integration requirement rather than silently shipping a cross-engine join — two of the three invented nothing, while the third flagged the gap but minted a provisional Snowflake name.

The scoreboard jump from ≤67% to ≥93% is not a model-quality effect; it reflects that, in this PoC, the registry surfaced governed authority and the required bindings — information that workspace search cannot supply, not even with the whole codebase in Scenario 1C. The two 93% scores (Sonnet and Opus) trail GPT's 100% by a single point each — the reproducible reporting date (C3): both anchored the output to `CURRENT_DATE()` instead of a parameterized as-of date, a production-reproducibility nit rather than a governed-reuse miss.

Scenario 2 was not flawless — the models needed steering on registry-readiness polish (a consistent namespace; a per-customer components grain; a reproducible as-of date), and one model minted a provisional Snowflake name for the missing cross-engine binding while still flagging it as a required integration step. None of it changed the outcome: every model produced the correctly-governed ARPAC composition — reusing the certified definitions and flagging, not faking, the one missing cross-engine binding, which stays an explicit integration precondition rather than a live cross-engine execution. And none of this replaces dbt or the semantic layer: those remain the primary mechanisms for implementing and consuming reuse, while the registry adds the organization-level *certified* status and the cross-engine, multi-implementation bindings that a single project graph or semantic layer does not hold (see [README §10](README.md), [poc-results.md](poc-results.md)). The PoC exercises an enterprise-wide canonical, but the same registry model also governs domain-scoped canonicals within a single domain — the adoption boundary is heterogeneity and criticality, not enterprise scope alone.

---

## Conclusions

The proof of concept is small and deliberately narrow — one metric, three models, single runs — but the pattern it reproduces is exactly the one the whitepaper predicts. **AI authoring cuts both ways.** Without reuse context, an assistant is a *duplication amplifier*: it generates plausible SQL from local files with no awareness that a canonical definition already exists, and it makes reimplementation cheaper than discovery. The same assistant becomes a *reuse accelerator* the moment the platform surfaces governed canonical definitions — not similar look-alikes of uncertain authority — directly in the authoring environment.

The deeper takeaway is that **reuse at authoring time is an authority problem, not a search problem.** AI answers "what looks similar." Governed reuse needs "what is approved, for what scope, bound to my runtime." Those are governance decisions, not properties of the implementation code, so widening the *code* context alone does not recover them — and, as Scenarios 1B and 1C show, it can make things worse by lending false confidence to retired, domain-local, or look-alike code, even when the entire codebase is in view.

The finding held **across every model tested**: every workspace-only run failed and every registry-aware run passed. This is a consistent pattern across the tested runs, not a universal benchmark — but the limitation it exposes is structural. A stronger model may make fewer local mistakes, yet it still cannot infer an artifact's authority, scope, ownership, or runtime bindings when those facts are not in the context it can see — which is why the gap does not simply close with the next release.

None of this is free, and the honest caveats matter. Declaration-layer manifests can rot unless they are **generated** from tool manifests rather than hand-maintained. Structural similarity is coarse — it catches copy-paste but misses semantically-equivalent rewrites, so those signals stay advisory. And the hard part of adoption is organizational — ownership, certification, and lifecycle governance — not the Python. This PoC proves the authoring-time half of the story; the runtime adoption-versus-bypass half is out of scope by design.

**If you want to move reuse upstream in your own platform**, the shape is small and additive:

1. Certify a small, high-impact set of artifacts first — start where inconsistency already costs you (a Tier-1 metric, a cross-domain definition), not everything.
2. Declare each one's identity, owner, lifecycle, reuse scope, contract source, and runtime bindings — generated from the tool manifests you already produce, not hand-maintained.
3. Expose intent discovery and binding resolution to the authoring environment, so referencing the certified artifact is the lowest-friction path.
4. Require unresolved scope or binding gaps to be explicit — flagged, never guessed.
5. Treat similarity signals as review and exception routing, not as proof of authority.

If your platform spans multiple engines, repositories, and BI tools, this is worth a look. The full registry concept is in the **whitepaper**; the working implementation, scenarios, and every recorded run are in the **[registry-aware-authoring](README.md)** directory of the repository.

👉 The model and registry concept: [The Data Platform DRY Model](https://michalpru.github.io/data-platform-dry-model/)

---

*Author's note: This article reflects my independent professional perspective, not that of any current or former employer, client, or vendor. The scenarios, data, and results are from a deliberately illustrative proof of concept. All text and diagrams are my own original work.*
