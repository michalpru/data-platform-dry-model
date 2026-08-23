# ARPAC Registry-Aware Authoring PoC — Architecture

> **Single source of truth** for this proof of concept. 
This PoC accompanies **Chapter 4 of the whitepaper** (*The Data Platform DRY Model — Phase II:
Operationalization*). On one concrete authoring task it shows how three levels of tooling change
whether an analytics engineer **reuses** certified definitions or silently **re-implements** them.

---

## 1. The authoring task — ARPAC

An analytics engineer must build **ARPAC — Average Revenue per Active Customer** (trailing 90 days)
for an executive dashboard. Two enterprise-certified concepts already exist and should be reused:

- **Net recognized revenue** — Finance-owned, on **Snowflake**. Assembled from a canonical
  billable-event stream and a certified recognition + currency rule.
- **Active customers** — the Sales-owned `sales.datasets.commercial_customer_status_90d.v1`
  (`is_active_commercial_90d`, 90-day commercial-activity window), on **Databricks**.

### ARPAC definition (canonical for this PoC)

$$\text{ARPAC}_{90d} = \frac{{ } \text{Net recognized revenue (USD) attributable to active customers}}{\bigl|\\ \text{Count of active customers}}$$

- **Numerator** — net recognized revenue in USD **attributable to active customers only**. Revenue
  from customers who are not commercially active in the window is excluded.
- **Denominator** — the count of customers active under the certified Sales
  `is_active_commercial_90d` definition.

This "active-only numerator" is the standard ARPAC convention (average revenue *per active
customer* should divide revenue **from** active customers by the number of active customers). It is
the definition materialized by the Scenario 2 generated artifacts. It is a deliberate, documented
choice; a variant that puts total recognized revenue over the active count is a different metric and
is not used here.

---

## 2. Execution platforms (engine map)

The registry is what unifies inputs that live on **different engines** — no single warehouse spans
them, which is precisely why a logical registry with resolvable bindings is needed.

| Domain / area | Execution engine | Dialect |
|---|---|---|
| Shared DWH (base tables) | Snowflake | Snowflake SQL |
| Finance (datasets + logic) | Snowflake | Snowflake SQL (+ dbt macro bindings) |
| Sales | Databricks | Spark SQL |
| Marketing | Databricks | Python / PySpark |
| Enterprise Analytics (consumer) | Snowflake | Snowflake SQL |

---

## 3. The registry principle

The DRY Artifact Registry is a **logical metadata index over existing repositories and platform
components**. It does **not** store or execute implementation code:

- Reusable artifacts have **logical identities** independent of physical implementations.
- **Implementation Bindings** point to physical implementations in code repositories, transformation
  projects, warehouses, semantic tools, or packages.
- The registry stores **only YAML manifests** (definitions + bindings). Each binding's `source`
  field is a *pointer* to the real code; the comparison engine reads that code to fingerprint it,
  but the registry itself holds none of it.
- SQLite plus deterministic AST / feature comparison is sufficient; a vector store is optional and
  advisory.

, 

---

## 4. The three scenarios

In this PoC the "existing repositories" are **mocked** as a per-scenario workspace tree (`registry-aware-authoring/scenarios/scenario-.../workspace/`).

- **Scenario 1 — workspace-only authoring.** Standard Copilot reasons over code available in the
  workspace to build the metric. **Scenario 1A — Workspace-only (base tables)** exposes base DWH
  tables only; **Scenario 1B — Workspace-only (base tables + domain repositories)** additionally
  exposes Finance and Marketing domain code.
- **Scenario 2 — Registry-aware authoring.** The DRY Artifact Registry (registry service methods +
  comparison service methods) is exposed through a thin MCP server and driven by the DRY Reuse agent
  (architecture in §7).

| Authoring setup | Scenario | Authoring mode | Exposed in the workspace | Likely / intended outcome |
|---|---|---|---|---|
| **Workspace-only (base tables)** | **1A** | Standard Copilot (workspace context + search) | Base DWH tables only (`dim_customers`, `fact_invoices`, `fact_refunds`) | Copilot re-codes ARPAC from first principles: invoice-based revenue, refunds ignored, invoice date as revenue date, and `dim_customers.is_active` (a 12-month order flag) misused as the active-customer definition. |
| **Workspace-only (base tables + domain repositories)** | **1B** | Standard Copilot (workspace context + search) | Base tables **+** Finance and Marketing domain repositories | Copilot reuses the most *similar* code it finds — the **retired** `finance.datasets.invoice_revenue` view and the Marketing-specific `active_customer` login rule — but similarity and availability do not indicate business authority. |
| **Registry-aware authoring** | **2** | Registry-aware custom agent (MCP intent lookup + code comparison) | The **registry** (logical artifacts + resolvable bindings). The registry manifests live alongside it in `registry-aware-authoring/scenarios/scenario-2/registry-manifests/` | The agent searches by intent, evaluates lifecycle/scope, resolves the certified Snowflake and Databricks bindings, and authors **only** the missing Enterprise composition. Nothing governed is re-implemented. |

The failure modes in 1A/1B are the point: **workspace similarity without governance can be worse
than authoring from scratch**, because it lends false confidence to retired or domain-specific code.

---

## 5. Artifact catalog

The **input registry** loaded by the PoC holds the nine artifacts below. The two Enterprise
Analytics artifacts are what **Scenario 2 generates** (they start absent).

| FQN | Interface | Kind / binding | Engine | Lifecycle | In input registry |
|---|---|---|---|---|---|
| `shared.datasets.dim_customers.v1` | queryable_dataset | table | Snowflake | certified | ✓ |
| `shared.datasets.fact_invoices.v1` | queryable_dataset | table | Snowflake | certified | ✓ |
| `shared.datasets.fact_refunds.v1` | queryable_dataset | table | Snowflake | certified | ✓ |
| `finance.datasets.dim_exchange_rates.v1` | queryable_dataset | table | Snowflake | certified | ✓ |
| `finance.datasets.fact_billable_events.v1` | queryable_dataset | table (invoices ∪ refunds) | Snowflake | certified | ✓ |
| `finance.datasets.invoice_revenue.v1` | queryable_dataset | view (**legacy**) | Snowflake | **retired** | ✓ |
| `finance.logic.normalize_currency.v1` | callable_logic | SQL table function **+** dbt macro | Snowflake | shared | ✓ |
| `finance.logic.recognize_revenue.v1` | callable_logic | SQL UDF **+** dbt macro | Snowflake | certified | ✓ |
| `sales.datasets.commercial_customer_status_90d.v1` | queryable_dataset | view | Databricks | certified | ✓ |
| `enterprise.datasets.customer_arpac_components_90d.v1` | queryable_dataset | composition dataset | Snowflake | certified | *generated (scenario 2)* |
| `enterprise.semantic.arpac_90d.v1` | semantic_contract | metric | Snowflake | certified | *generated (scenario 2)* |

### Dependency shape (revenue side)

```
shared.datasets.fact_invoices ─┐
                               ├─▶ finance.datasets.fact_billable_events ─▶ finance.logic.recognize_revenue ─▶ enterprise.datasets.customer_arpac_components_90d ─▶ enterprise.semantic.arpac_90d
shared.datasets.fact_refunds ──┘                                              ▲
finance.datasets.dim_exchange_rates ─▶ finance.logic.normalize_currency ──────┘
sales.datasets.commercial_customer_status_90d ───────────────────────────────▶ enterprise.datasets.customer_arpac_components_90d
```

`fact_billable_events` is the canonical, standardized event stream (invoice + refund/credit-note
events with signed amounts). `recognize_revenue` reads it and normalizes each amount to USD via
`normalize_currency`; consumers must **not** re-derive revenue from raw invoices/refunds. The retired
`invoice_revenue` view is kept on purpose so registry-aware authoring can **reject** it.

### One logical identity, multiple bindings

`finance.logic.recognize_revenue.v1` and `finance.logic.normalize_currency.v1` each expose **two
Snowflake-stack bindings** — a native warehouse object and a dbt macro that reuses the exact same
rule. `resolve_binding` returns the dbt macro for a dbt runtime and the native object for a raw
warehouse runtime. dbt gives reuse *inside* dbt on one engine; the registry records that the macro
and the native object are the **same certified capability** and additionally spans the Databricks
stack that dbt-on-Snowflake never sees.

---

## 6. Directory layout

```
registry-aware-authoring/
  README.md                      ← this file (single source of truth)
  registry/                      ← the DRY Artifact Registry engine + Lookup & Compare Service
    dry_registry/
      manifests.py               ← loads DryArtifact YAML; MANIFESTS_DIR + WORKSPACE_DIR anchors
      store.py                   ← SQLite control plane + FTS5 search
      models.py                  ← JSON-serialisable result shapes (shared by CLI + MCP)
      comparison/                ← the ONE shared comparison core
        normalizers/             ← SQL (sqlglot) + Python (ast) normalization
        features/                ← language-neutral transformation profile
        scorers/                 ← ast (token-seq), feature (Jaccard), embedding (on-demand)
        ranking.py, classification.py, engine.py
      candidate_providers/       ← registry_provider + workspace_provider (same engine)
      services/                  ← RegistryService, BindingService, ReuseDetectionService
      cli.py                     ← THIN client over the services (never uses MCP)
      mcp_server.py              ← THIN stdio MCP proxy over the services (registry scope)
    pyproject.toml               ← zero required ML deps; optional [sql] [vector] [mcp] extras
    tests/                       ← invariant tests (offline)
  demo-walkthrough.md            ← the three-scenario walkthrough with commands + real output
  scenarios/                     ← the three workspaces the assistant "sees"
    scenario-1a/                 ← base warehouse tables only
    scenario-1b/                 ← base tables + finance & marketing domain repos
    scenario-2/                  ← registry-aware
      registry-manifests/        ← the PoC registry: PURE YAML DryArtifact manifests, no code
        shared/                  ← base-table manifests (dim_customers, fact_invoices, fact_refunds, dim_exchange_rates)
        domains/finance/         ← finance datasets + logic manifests
        domains/sales/           ← sales dataset manifest
      workspace/                 ← the mocked code the bindings point at
        dwh/shared/datasets/     ← base-table DDL (Snowflake)
        finance/{datasets,logic} ← finance code (Snowflake + dbt macros)
        sales/datasets/          ← commercial_customer_status_90d (Databricks)
        enterprise/{datasets,semantic} ← EMPTY authoring target (agent writes here)
.github/agents/dry-reuse.agent.md         ← Copilot custom agent (registry-aware authoring)
.github/prompts/search-registry.prompt.md ← intent-first workflow
.github/prompts/compare-with-registry.prompt.md ← code-first workflow
.vscode/mcp.json                          ← registers the local stdio MCP server
```

**Placement rules.** PoC code artifacts (functions, datasets) live under
`scenarios/<scenario>/workspace/` and may be **duplicated across scenarios**. Registry definitions
are pure YAML under `scenarios/scenario-2/registry-manifests/`. Generic, non-PoC artifacts and
platform packages live in `../dry-reference-repository/` (each top-level folder simulates a separate
team repository) and are **not** part of the PoC's loaded registry.

---

## 7. Scenario 2 architecture (registry-aware authoring)

> **Registry** knows *what exists* (start here) · the **comparison service** *verifies* what is
> similar · the **DRY Reuse agent** knows *how to help the engineer use both*.

Scenario 2 exposes the DRY Artifact Registry to the engineer as a layered stack — registry service
methods and comparison service methods over the store, a thin MCP server that makes them callable as
structured tools, and the DRY Reuse agent that drives the workflow:

```
        DRY Reuse agent   —  Discover → Resolve → Compose → Verify
                │  structured tool calls
     ┌──────────┴───────────┐  thin MCP server  (.vscode/mcp.json, stdio; no business logic)
     ▼                      ▼
 registry service      comparison service
 methods               methods
  search_artifacts       compare_code
  get_artifact           (shared AST + feature engine;
  find_composable_...      similarity + governance)
  recommend_composition
  resolve_binding
     └──────────┬───────────┘
        DRY Artifact Registry   —  SQLite control plane + FTS5 over pure-YAML manifests
                │  each binding.source is a pointer
        workspace/ implementation code  —  read at authoring time to confirm signatures
```

1. **DRY Artifact Registry** — a SQLite control plane with an FTS5 index built by `ingest` from the
   pure-YAML DryArtifact manifests. It holds logical identities, authority (lifecycle / owner / reuse
   intent), bindings and dependency edges — never implementation code.
2. **Registry service methods** (`RegistryService`, `BindingService`) — intent discovery and binding
   resolution: `search_artifacts`, `get_artifact`, `find_composable_artifacts`,
   `recommend_composition`, `resolve_binding`.
3. **Comparison service methods** (`ReuseDetectionService`) — code-first verification: `compare_code`
   fingerprints candidate code with the shared AST/feature engine and returns similarity **plus**
   governance evidence.
4. **Thin MCP server** — a stdio proxy (registered in `.vscode/mcp.json`) that exposes both service
   groups as structured MCP tools. It holds no business logic; it forwards typed calls to the
   services and returns their JSON payloads. The CLI is the *same* thin client without MCP.
5. **DRY Reuse agent** — the custom Copilot agent that orchestrates Discover → Resolve → Compose →
   Verify with those tools, reads each resolved binding's `source` at authoring time to confirm
   columns/signatures, and writes the governed composition.

Both thin clients (CLI and MCP server) share the same application services
(`dry_registry.services`). Business logic — normalization, feature extraction, scoring, ranking,
classification — lives **once** in the shared comparison core. Only the *candidate source* and the
*governance metadata* differ by scope:

- **Registry scope** — candidates are governed logical artifacts (authority, lifecycle, owner, reuse
  intent, recommended binding); source code is read from the workspace via each binding's `source`
  pointer. This is the scope Scenario 2 uses.
- **Workspace scope** — candidates are raw files with **no** governance (`UNKNOWN`) and explicit
  coverage warnings — the same "similarity without authority" gap Scenario 1B hits, available here as
  a contrast via `compare --scope workspace`.

Two environment-overridable anchors decouple definitions from code:

- `DRY_MANIFESTS_DIR` (default `registry-aware-authoring/scenarios/scenario-2/registry-manifests`) — where the pure-YAML
  manifests live. The loader walks it recursively for every `kind: DryArtifact` document.
- `DRY_WORKSPACE_DIR` (default `registry-aware-authoring/scenarios/scenario-2/workspace`) — the root that each binding's
  `source` path is resolved against.

The Python services **never call an LLM**. They return structured evidence; the DRY Reuse agent reads
that evidence and explains/acts. The agent is taught the *workflow and the tools*, never the registry
contents.

---

## 8. Running the PoC

```powershell
# from registry-aware-authoring/registry
pip install -e ".[sql]"                # add ,vector for embeddings; ,mcp for the server
python -m dry_registry.cli --db "$pwd\.dry_registry.sqlite" ingest   # write to the path mcp.json expects

# intent-first discovery + composition
python -m dry_registry.cli search "recognize revenue"
python -m dry_registry.cli recommend "ARPAC" --component "net recognized revenue" --component "active customers"
python -m dry_registry.cli resolve-binding finance.logic.recognize_revenue.v1 --runtime dbt

# reuse detection (verification)
python -m dry_registry.cli compare selected.sql --scope registry
```

Add `--json` to any command to get the raw structured payload the MCP tools also return.

**Registry-aware authoring through the DRY Reuse agent (Scenario 2):** `pip install -e ".[sql,mcp]"`, then
run `python -m dry_registry.cli --db "$pwd\.dry_registry.sqlite" ingest` from `registry-aware-authoring/registry`,
reload VS Code (**Ctrl+Shift+P** → Developer: Reload Window) so `.vscode/mcp.json` starts the
`dry-registry` MCP server, open Copilot Chat, pick the **DRY Reuse** agent, attach
`.vscode/mcp.json` and `.github/agents/dry-reuse.agent.md` to the chat context, and use
`/search-registry` (intent-first) or `/compare-with-registry` (code-first).

See [demo-walkthrough.md](demo-walkthrough.md) for the full narrative with real output.

---

## 9. Design choices

- **Fully local, zero cloud.** SQLite control plane; AST / structural similarity via the Python
  stdlib and `sqlglot`. No vector store, graph DB or remote service is required to run the demo.
- **AST is the default signal; embeddings are advisory.** The deterministic AST/feature baseline
  catches copy-paste and near-duplicates with zero ML dependencies. The optional `[vector]` extra
  computes embeddings of the extracted transformation profile per run and discards them (no vector
  DB, no persistence); its output is always advisory and never blocks on its own, consistent with
  the whitepaper.
- **`compare_code` is the whitepaper's build-time detection, moved to authoring time — and it is
  verified.** The whitepaper's §4.3.3 duplication-detection techniques (AST structural
  fingerprinting, advisory embedding similarity, advisory LLM analysis, all routing to review) are
  implemented by the shared comparison engine and run at authoring time rather than only in a CI
  gate: `ast_scorer` (`sqlglot`/Python `ast`, normalized), the optional advisory embedding tier, a
  language-neutral `feature_scorer` for cross-language pairs, and — kept deliberately separate — the
  DRY Reuse **agent** as the LLM that reasons over the structured evidence (the Python services never
  call an LLM). A recorded [verification battery](scenarios/scenario-2/verification/) proves the
  detector fires with positive *and* negative controls (a retired-artifact reimplementation and a
  reformatted certified UDF are both caught; the three composed Scenario 2 outputs return *safe to
  author*). Exercising it via the CLI as the closing Verify step — versus auto-invoking and
  persisting the verdict on every generated artifact — is still an open step.
- **Scoring target differs from the whitepaper by design (persisted vs. on-the-fly).** A production
  build-time gate would typically score a candidate against **persisted derived signals** —
  normalized AST fingerprints, and (for embedding similarity) a stored vector corpus keyed to
  logical identity and embedding-model version — fed by a separate ingestion step rather than
  re-reading every repository. The whitepaper supports retaining such derived signals (and notes a
  stored embedding corpus must be re-embedded after a model-version change), and treats a vector
  store as needed only for advanced similarity, not as a universal requirement; it does not mandate
  that every AST fingerprint be a persisted registry record. This PoC keeps **no fingerprint or
  vector store**: at `compare_code` time it reads each registered artifact's source (via a
  representative binding's `source` pointer) from the workspace and computes both the AST fingerprint
  and any embeddings on the fly, then discards them. The comparison is fingerprint-vs-fingerprint
  either way; only *where* each side's fingerprint comes from changes. That per-binding `source`
  pointer is itself a PoC extension — the whitepaper's binding names the deployed object plus an
  attribution key, with source reached via repository-scan connectors.
- **The registry is a reuse-control overlay, not a new catalog or a second transformation tool.**
  It ingests the declaration-layer YAML teams already write and adds only the reuse-governance
  fields (lifecycle, canonical status, bindings, dependency edges). In an operational system those
  `spec` blocks are *generated* from tool manifests (`dbt ls --output json`, `manifest.json`), not
  hand-authored. It never executes anything.
- **Comparison returns logical artifacts, not bindings.** An artifact with several bindings (a
  warehouse UDF *and* a dbt macro) is compared once and reported once; `resolve_binding` then
  selects the physical object for the engineer's runtime/dialect. Reusing the dbt macro in a dbt
  model is therefore not flagged as duplication — only re-derivation from raw tables is.
- **Similarity is described honestly** as AST/parser-normalized token-sequence similarity — not
  full semantic equivalence. Cross-language pairs (SQL vs Python) have no AST score and fall back
  to the language-neutral feature/embedding signal.

---

## 10. Why not just dbt or the semantic layer?

The most common objection is *"we already do this with dbt macros, models and the semantic layer."*
Those tools are complementary, not a replacement — the registry closes gaps they structurally cannot:

1. **dbt governs a project; the failure modes are cross-project and cross-engine.** dbt Mesh /
   `ref()` / package pins work inside one project's DAG on one warehouse. This PoC's ARPAC spans
   **two engines** — net recognized revenue on **Snowflake** and the certified active-customer
   status on **Databricks**, which has no Snowflake binding. The registry *surfaces* that
   cross-engine gap (provisioning a bridge is a separate integration task, out of scope here); its
   unit is a *logical identity with bindings across engines*, whereas dbt's unit is a node in one
   project's graph.
2. **A macro/model is not a metric; the semantic layer is not org-wide.** Macros give DRY in Code,
   models give DRY in Logic, MetricFlow gives DRY in Semantics — but only for consumers that go
   through it. The active-customer divergence (`dim_customers.is_active`, a 12-month operational
   flag, vs the certified 90-day commercial-activity status) happens the moment someone queries the
   base table directly in a notebook, which the semantic layer cannot prevent.
3. **"Reused" and "certified" are different claims.** A dbt model being `ref`-able does not tell you
   it is the *certified* definition, its lifecycle state, or who bypassed it. dbt's `unique_id` is
   project-scoped; there is no org-scoped, version-pinned canonical status. That reuse-control
   metadata is what the registry adds and nothing else in the stack holds.
4. **The registry is additive.** A dbt shop keeps dbt: the registry indexes the manifest, adds
   lifecycle / canonical status / bindings, and extends the same governance to Spark and
   warehouse-native objects. Lower barrier to adoption because nothing is replaced.
5. **Observe broadly, enforce narrowly.** Only Tier-1, cross-domain, executive/regulated
   definitions warrant this. For a single-warehouse, single-BI, all-dbt shop the ROI is genuinely
   low. The value scales with heterogeneity (multi-engine, multi-BI, multi-repo) — the
   large-platform context this model targets.

---

## 11. Where the value is real, and known limitations

**Real value.** Authoring-time prevention beats post-hoc detection — resolving the canonical
artifact *before* code is written is a different economic model, and AI assistants make it cheap.
One logical identity across engines/dialects addresses a problem current tools handle poorly. And
the registry adds *similarity **plus** authority* (which definition is certified and who owns it),
where workspace search gives similarity alone.

**Known limitations (acknowledged up front).**

- **Manifests can rot** — declaration-layer YAML is only as good as the discipline maintaining it;
  generating it from tool manifests is the mitigation.
- **Structural similarity is coarse** — AST catches copy-paste and near-duplicates but misses
  semantically-equivalent rewrites; embeddings produce false positives on short/generic SQL. Both
  stay advisory for that reason.
- **Adoption cost is organizational, not technical** — ownership, certification and the governance
  process are the hard part, not the Python here.
- **Behavioral signals are out of scope by design** — this PoC proves the authoring-time half of the
  story; adoption-vs-bypass telemetry (the runtime-bypass half) is stubbed via bindings only.
