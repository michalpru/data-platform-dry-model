# AI-assisted authoring for governed reuse in data platforms

*A proof of concept implementing the DRY Artifact Registry for AI-assisted authoring — what context is missing, and what changes when you add it.*

*Version 0.1 (draft) · August 2026*

---

## 1. An analytics engineer is asked for one number

An analytics engineer is handed a familiar task: build **ARPAC: Average Revenue per Active Customer** (trailing 90 days) for an executive dashboard. 
They open their IDE, describe the metric to an AI coding assistant and let it draft the SQL.

ARPAC does not exist yet as a governed metric. But its parts do. **Net recognized revenue** and **active customers** are among the most reused concepts in any company, defined and redefined across warehouses, notebooks, and BI tools. Each typically has several valid but different definitions: some intentionally scoped to a domain like Marketing or Finance rather than approved company-wide, others legacy or retired code still sitting in repositories or warehouses where an AI coding assistant can mistake them for valid reuse candidates.

So the real task is not to write ARPAC from scratch. It is "**compose ARPAC for executive reporting from the relevant functions or datasets already approved as company-wide canonicals**." That is a reuse problem, and it is exactly where AI-assisted authoring is supposed to help.

---

This article reports a small proof of concept that tested how well it does. The result is the interesting part: when the AI coding assistant could use only the code available in its workspace, **none of the models produced the correct governed metric**, even when that workspace contained the *entire* codebase. More code improved partial correctness, but it neither identified the governed definition the metric required nor resolved the missing runtime binding for it.

---

## 2. The test: one metric, three models, four setups
The diagram below maps the ARPAC use case across the enterprise data platform, highlighting the artifacts exposed for AI coding assistant and the two certified enterprise definitions (marked green) that the governed metric should reuse. Additionally it has been assumed that the company uses different tools/enignes to test how AI models will handle cross-platform bindings. Snowflake and Databricks have been chosen as examples.

<img src="../publications/assets-diagrams/registry-aware-authoring-poc-scenarios.jpg" alt="Data Landscape In The PoC" width="80%">

The PoC runs the same ARPAC task through four authoring setups and three current models: **GPT-5.5**, **Claude Sonnet 4.6**, and **Claude Opus 4.8**. In this Poc the GitHub Copilot was used with VS Code IDE. Below are the certain artifacts exposed for the models:

| Authoring setup | Scenario | What the AI coding assistant can use |
|---|---|---|
| **Workspace-only**<br>base tables | **Scenario 1A** | The shared warehouse base tables: `dim_customers`, `fact_invoices`, and `fact_refunds` |
| **Workspace-only**<br>base tables + domain repositories | **Scenario 1B** | The base tables plus chosen Finance and Marketing domain code, so the assistant can find similar existing logic |
| **Workspace-only**<br>all existing codebase | **Scenario 1C** | The **entire codebase** across every domain, including the certified recognition logic and active-customer definition as source. This is the most optimistic workspace assumption |
| **Registry-aware authoring** | **Scenario 2** | The **DRY Artifact Registry**, exposed as structured tools over a thin MCP server and driven by the custom **DRY Reuse agent** |

### Authoring-time Reuse Architecture 
This diagram depicts what is exposed to an AI coding assistant when an analytics engineer performs their task:
-  Code workspace-only: Scenarios 1A/1B/1C
- Registry-aware authoring: Scenario 2

<img src="../publications/assets-diagrams/authoring-time-reuse-architecture.jpg" alt="Authoring-time Reuse Architecture" width="75%">

### Prompts
The prompt is the same business intent in every run: "I need a trailing-90-day ARPAC metric for executive reporting...
- Numerator = net recognized revenue in USD, over the trailing 90 days, counting *only* active customers
- Denominator = the count of active customers using the definition used in other executive dashboards... 
Reuse existing definitions, datasets, or functions where appropriate, and explain what was reused"

Full prompts and recorded runs are documented in [demo walkthrough](demo-walkthrough.md). 
Each scenario's repositories are mocked and deliberately scoped, so the **test isolates which context the assistant can reach.**

---

## 3. PoC Results: Why exposing only the code workspace to AI Coding Asssitant doesn't deliver governed reuse

### Scenario 1A: Code workspace-only with base tables

This is the baseline. With only base tables visible and nothing reusable to find, every model builds ARPAC from first principles:
- Silently **re-implements three governed rules**: billable-event assembly, revenue recognition, currency normalization
- Picks the **wrong active-customer definition**: `dim_customers.is_active`, a 12-month order flag, not the certified 90-day commercial status. 
The SQL runs and looks correct, and none of the models flagged the active-customer definition as ungoverned: GPT framed `is_active` as the "executive-aligned", and Opus went further, calling it "the enterprise active-customer definition", so the result reads as trustworthy even as two dashboards quietly diverge. 

That is the **duplication amplifier**: with nothing certified to reuse, the assistant re-derives governed logic and no one notices.

See the [Recorded run](demo-walkthrough.md#scenario-1a--workspace-only-base-tables), and the [Detailed Scenario 1A per-model results](poc-results.md#scenario-1a--base-dwh-tables-only).


### Scenario 1B: Code workspace-only with base tables and domain repositories

The obvious fix is to give the AI coding assistant more to work with, so Scenario 1B adds some artifacts (functions and datasets) from the domain repositories. 

With domain code visible, the models found similar artifacts and reused them — the wrong ones:
- The Finance repo contains `invoice_revenue`: a **retired** view that skips refunds. Nothing in the code repository says "retired," so models reused it and reproduced a known defect
- The Marketing repo contains a **domain-local**, login-based active-customer rule. Two of the three models translated it to SQL and explicitly labelled it *"the authoritative active-customer definition used by executive dashboards."*
- Meanwhile the composables actually needed (the enterprise-level canonicals) were **invisible to workspace search**, because they existed only as deployed warehouse objects or in repositories that were never checked out.

This is where the result becomes counter-intuitive. **More context did not fix the answer, but it made the wrong one more convincing.**

See the [Recorded run](demo-walkthrough.md#scenario-1b--workspace-only-base-tables--domain-repositories), and the [Detailed Scenario 1B results and per-model analysis](scenarios/scenario-1b/README.md).


### Scenario 1C: Code workspace-only with all existing codebase

Scenario 1C grants the **most optimistic** workspace assumption possible: the AI assistant sees the **entire* codebase at once**: every domain repository checked out and every warehouse object exposed as source, including the needed composables: certified `recognize_revenue` UDF and `commercial_customer_status_90d` view.
Even so, **it still does not compose the metric correctly**.
- **What went right**: All models finally get the **numerator** right. They discover and reuse the certified `recognize_revenue`, so revenue recognition, refund netting, and currency normalization are delegated rather than re-derived.
- **What fails again, and more instructively**: Every model chose the plausible Sales-owned look-alike "active customer" definition over the certified view. Two things drove the choice: the models read and cast the look-alike as the "executive-reporting aligned" rule, and where a model did weigh the certified view, it rejected it as non-runnable, because it depends on upstream tables not materialized in the workspace. Authority never entered in, as nothing in the source encodes it.

The 1C output only looks more trustworthy than it did in the previous scenarios: a certified numerator, a clean composition, confident commentary, even as it silently uses the wrong denominator, understating the active-customer count and overstating ARPAC. **More visible code bought more convincing output, not a correct one**.

See the [Recorded run](demo-walkthrough.md#scenario-1c--workspace-only-all-existing-codebase), and the [Detailed Scenario 1C results and per-model analysis](scenarios/scenario-1c/poc-results/README.md).

### The failure modes, in one place
Across the runs, the workspace-only setups fail in four recurring ways (even when the SQL syntax is correct):
- **Re-deriving governed logic** from raw tables (recognition, refund netting, currency, activity window)
- **Reusing similar-but-wrong artifacts**: a retired view, or a domain-local rule promoted to an enterprise canonical
- **Cross-engine and composition defects**: combining a Snowflake revenue-recognition UDF with a Databricks active-customer view as if a cross-engine binding existed
- **False confidence**: a well-commented result presented with no governance caveat


### What AI cannot infer from code alone
Even when an AI coding assistant can search the exposed domain code, workspace search ranks matches only by textual and structural similarity. The decisive information is **not in the source**. Even with perfect search over every repository, an assistant cannot read off:
- **Authority**: is this the approved, canonical definition for this scope, or a convincing look-alike?
- **Reuse intent and scope**: was this built to be reused enterprise-wide, within one domain, or never?
- **Lifecycle**: is it shared, certified, deprecated, or retired?
- **Ownership**: who is accountable for it, and can approve a change?
- **Implementation bindings**: even if the right logic is found, how is it consumed from the engineer's runtime and dialect?

AI-assisted authoring makes it **cheap to write code and to find something that looks reusable**. It does not answer the question the task actually turns on: **what should be reused.** That answer requires governance context that spans the repositories, and typically does not live in any of them.

### Reachability
Furthermore, assuming an assistant will search every relevant repository and every deployed warehouse object across every domain is not realistic. Widening the workspace does not resolve this; it just adds more places a retired, local, or irrelevant artifact can be picked up with false confidence.


### The scoreboard

Scored on one deliberately harsh grading question: **did it deliver the correct, governed ARPAC ?** The workspace-only setups fail for every model:

| Model | 1A (base tables) | 1B (base tables + selected domain repos) | 1C (all existing codebase) | **2 (registry-aware)** |
|---|:--:|:--:|:--:|:--:|
| **GPT-5.5** | 27% | 40% | 60% | **100%** |
| **Claude Sonnet 4.6** | 27% | 33% | 67% | **93%** |
| **Claude Opus 4.8** | 27% | 33% | 67% | **93%** |

Each percentage is the run's score on a **15-point rubric**, with points spread across the governed components (recognition, refund netting, currency, activity window, the certified active-customer definition, and composition/binding). A particular component that is wrong, or that relies on an artifact the assistant couldn't reach, loses only its own points, not the whole run; the components a run gets right still count. That is why the workspace-only setups land at partial scores rather than 0%, and only an all-correct run reaches 100%. 
The [full rubric and point-by-point breakdown](poc-results.md#4-scoring-matrix) has the details.

The verdict is the same for every workspace-only run: **no governed ARPAC.** The climb from 1A (27%) to 1B (33–40%) to 1C (60–67%) is real but partial — more visible code raises partial correctness, and confidence, but never reaches a correct result.

These results are **use-case-specific**, not a benchmark: a different mix of visible artifacts could score higher or lower. What repeats is the tendency — when several plausible definitions exist, code access alone cannot establish which one is authoritative, or how to bind it to the target runtime.

---

## 4. The governance control plane: exposing the registry to AI coding assistant

### What the Registry is

The PoC uses a small **DRY Artifact Registry**, which is the **reuse-governance control plane** introduced in the [Whitepaper](https://michalpru.github.io/data-platform-dry-model/publications/whitepaper-data-platform-dry-model.html#the-missing-control-plane-for-reuse-measurement). It is not a new warehouse, catalog, or code store. It is a **vendor-neutral metadata layer** that gives each reusable artifact a stable logical identity, lifecycle, reuse scope, owner, and implementation bindings — the pointers to the physical objects. 
It governs three reuse interfaces: **callable logic, queryable datasets, and semantic contracts**. It stores metadata, and derived signals such as structural fingerprints, but never the implementation code and it never sits in the query-execution path.

<img src="../publications/assets-diagrams/dry-artifact-registry.jpg" width="800"/>

**The Registry is not RAG:** retrieval can surface registry records, but it cannot by itself certify an artifact, select a runtime binding, or establish ownership and lifecycle accountability. 

Warehouse- and catalog-backed **MCP servers** may expose deployed objects, schemas, lineage, and some of these governance facts, potentially closing the reachability gap in Scenarios 1A–1C. This PoC does not compare those tools. **The Registry’s role is to normalize the required reuse-governance metadata from code repositories, warehouses, catalogs, and lineage systems, so an AI assistant doesn't need to infer them from disparate sources.**

### Workspace code search vs. Registry resolution

Workspace code search answers ”what looks similar?” The registry answers the governed question: **”which artifact is approved for this scope, and how is it consumed from this runtime?”** Both find candidates; only the registry carries authority.

| | Workspace similarity search | Registry-backed resolution |
|---|---|---|
| **Finds** | Structurally/textually similar code | The governed artifact for the intent |
| **Coverage** | Only repositories open in the workspace | Every registered artifact, across engines |
| **Authority signal** | None: lifecycle/owner/scope unknown | Certified vs. retired vs. domain-local, with owner |
| **Runtime fit** | Raw file; consumer resolves it | `resolve_binding` points to the deployed object for the runtime/dialect |
| **Failure mode** | Confident reuse of the wrong artifact | Flags gaps (e.g. missing cross-engine binding) instead of guessing |

Workspace search curbs accidental re-implementation; registry resolution makes reuse of the canonical artifact the lowest-friction path.

### What exactly was implemented in the PoC

The PoC exposes the Registry to the assistant as a thin, layered stack:

![PoC architecture: registry services and comparison services, a thin MCP server, and the DRY Reuse agent](../publications/assets-diagrams/registry-aware-authoring-poc-architecture.jpg)

- **The Registry**: a local SQLite control plane built from pure-YAML artifact manifests. It holds logical identities, authority, bindings, and dependency edges; each binding points to real code in the workspace but the registry holds none of it
- **Registry service methods**: intent-first discovery and binding resolution: `search_artifacts`, `find_composable_artifacts`, `recommend_composition`, `resolve_binding`
- **Comparison service methods**: code-first verification: `compare_code` fingerprints authored code with a shared AST/feature engine and returns similarity **plus** governance evidence
- **A thin MCP server**: exposes both service groups as structured tools; it holds no business logic
- **The DRY Reuse agent**: a custom Copilot agent whose instructions drive the workflow and read each resolved binding's source to confirm columns and signatures before referencing them

Notably, the Python services **never call an LLM**. They return structured evidence; the agent reads that evidence and acts. The determinism lives in the tools; the language understanding lives in the model.

### The agent workflow

The [DRY Reuse agent](../.github/agents/dry-reuse.agent.md) runs **two paths** over the same registry services, chosen by how a data/analytics engineer starts.

### 1. Intent-first agent workflow
The default, when the engineer describes what to build.

**Business intent → Discover → Plan composition → Resolve bindings → Confirm interface → Compose → Verify.** 

Its system instructions enforce the discipline: search the registry before writing code, prefer a complete artifact over composable parts, resolve each binding for the target runtime, confirm interface contracts from source rather than memory, never fabricate a cross-engine bridge, and compare the finished code back against the registry.

For the ARPAC use case in this PoC, discovery finds no existing metric, so the agent decomposes the formula into its two named components and calls `recommend_composition`, which resolves each to its **enterprise-wide certified** definition and binding — the domain-canonical `fact_billable_events` and the raw `dim_customers.is_active` flag are deliberately **not** selected for an executive metric.

### 2. Code-first agent workflow
When the engineer already has code and asks *"does this already exist?"*

**Compare → Explain evidence → Resolve binding → Recommend reuse.** 

The `compare_code` fingerprints the code with a shared AST/feature engine — plus an optional, advisory **embedding** signal for rewrites the AST would miss — and scores it against every registered artifact. It returns not just a similarity number but the **governance evidence** behind each match: the artifact it resembles, its lifecycle and owner, and a recommended action. Similarity is only a candidate; authority still comes from the registry, not the score. These are the whitepaper's build-time duplication-detection signals (§4.3.3) brought forward to authoring time; a recorded [verification suite](scenarios/scenario-2/code-similarity-verification/) confirms the detector both fires on real duplication and stays quiet on correctly-composed reuse.

The same `compare_code` call is also the intent-first path's closing **Verify** step. Run over the Scenario 2 SQL it returns *no strong match, safe to author* — the revenue, netting, currency and activity-window rules are referenced, not re-derived. One honest gap remains: in these runs Verify ran through the CLI, so wiring the agent to run **and persist** that verdict with every generated artifact is still open.


### Beyond the agent: the same services from the CLI

The MCP server and the CLI are thin clients over the **same** Lookup & Compare services, so an engineer does not need the agent to use them. `search`, `recommend`, `resolve-binding`, and `compare` are callable from the command line for an ad-hoc check at authoring time, or as a build-time CI gate so the same comparison fires before merge.


### Registry-aware authoring (Scenario 2): Results

**Decisive verdict: correct governed ARPAC — Yes for all three models; both registered decoys rejected.**

| Scenario | GPT-5.5 | Sonnet 4.6 | Opus 4.8 |
|---|:--:|:--:|:--:|
| 1A | ❌ No | ❌ No | ❌ No |
| 1B | ❌ No | ❌ No | ❌ No |
| 1C | ❌ No | ❌ No | ❌ No |
| 2 | ✅ Yes | ✅ Yes | ✅ Yes |

The outcome held across all three models. Every one:

- reused the certified `recognize_revenue` (numerator) and `commercial_customer_status_90d` (denominator), authoring **only** the missing ARPAC ratio;
- rejected the retired `invoice_revenue` view and the base-table re-derivation that 1A/1B fell into;
- rejected the two newly registered domain-local look-alikes — the Sales billed proxy and the Marketing login proxy — while retaining the certified enterprise denominator;
- resolved the registered Snowflake UDF binding for revenue and the Databricks view binding for active status, so the certified definitions were referenced rather than re-implemented;
- and, when the active-customer status resolved only to Databricks while the target engine was Snowflake, surfaced the missing binding as an integration requirement rather than silently shipping a cross-engine join — two of the three invented nothing, while the third flagged the gap but minted a provisional Snowflake name.

The scoreboard jump from ≤67% to ≥93% is not a model-quality effect; it reflects that, in this PoC, the registry surfaced governed authority and the required bindings — information that workspace search cannot supply. Scenario 1C and Scenario 2 see the same underlying code, yet only the registry-backed run composed the governed metric: reaching an object is not the same as knowing which definition is authoritative and how to bind it. The two 93% scores (Sonnet and Opus) trail GPT's 100% by a single point each — the reproducible reporting date (C3): both anchored the output to `CURRENT_DATE()` instead of a parameterized as-of date, a production-reproducibility nit rather than a governed-reuse miss.

Scenario 2 was not flawless — the models needed steering on registry-readiness polish (a consistent namespace; a per-customer components grain; a reproducible as-of date), and one model minted a provisional Snowflake name for the missing cross-engine binding while still flagging it as a required integration step. None of it changed the outcome: every model produced the correctly-governed ARPAC composition — reusing the certified definitions and flagging, not faking, the one missing cross-engine binding, which stays an explicit integration precondition rather than a live cross-engine execution. And none of this replaces dbt or the semantic layer: those remain the primary mechanisms for implementing and consuming reuse, while the registry adds the organization-level *certified* status and the cross-engine, multi-implementation bindings that a single project graph or semantic layer does not hold (see [README §10](README.md), [poc-results.md](poc-results.md)). The PoC exercises an enterprise-wide canonical, but the same registry model also governs domain-scoped canonicals within a single domain — the adoption boundary is heterogeneity and criticality, not enterprise scope alone.

See the [recorded run and VS Code screenshots](demo-walkthrough.md#scenario-2--registry-aware-authoring), and the [detailed Scenario 2 per-model results](poc-results.md#scenario-2--registry-aware-authoring).

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
