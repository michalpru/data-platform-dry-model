# Three-scenario walkthrough: authoring ARPAC

> Task: build **ARPAC = Average Revenue per Active Customer** for the executive dashboard,
> reusing enterprise-certified definitions instead of rebuilding them.

The three scenarios map to the authoring-time rows of the whitepaper's *Duplication Detection and
Prevention Techniques* table (§4.3.3). Scenarios 1A and 1B have no registry access. Scenario 2
is **registry-backed canonical resolution** (high confidence, prevention at authoring time).

> **How this PoC extends the whitepaper.** In the whitepaper, the three *detection techniques* —
> structural fingerprinting (AST), embedding-based similarity, and LLM-based analysis — sit at
> **build time**, inside the CI/CD *Duplication Detection and Prevention Flow*. This PoC brings
> those same techniques **forward to authoring time**: the AST engine that a CI gate would run
> post-hoc is the same engine powering the workspace search and the registry `compare` check here
> — so a likely reimplementation surfaces while the engineer is still typing, not only after the
> PR is opened.
>
> **Two integration surfaces.** Scenarios 1A/1B use standard Copilot with workspace file context.
> Scenario 2 uses a **custom DRY Reuse agent** over a thin MCP server for registry-aware authoring.

---

## The prompt

Three models were tested in each scenario: **GPT-5.5**, **Claude Sonnet 4.6**, and **Claude Opus 4.8**.

### Scenarios 1A and 1B — base prompt

```
I need a trailing-90-day ARPAC (Average Revenue per Active Customer) metric for executive reporting. Deliver a reusable ARPAC metric definition that other executive dashboards can adopt.
- Reuse existing definitions, datasets, or functions where appropriate, and explain what was reused.
- ARPAC = net recognized revenue in USD (numerator) divided by the number of active customers (denominator).
- Denominator = the distinct count of active customers, using the active-customer definition aligned with the one currently used in other executive dashboards.
- Numerator = net recognized revenue in USD over the trailing 90 days, counting ONLY revenue from the customers in the denominator. Revenue from non-active customers is excluded.

To accomplish this task please use only the code in the /poc/scenarios/<scenario>/workspace directory. Please ignore all other files from other directories.

Do NOT use the DRY registry or any MCP tools (e.g. search_artifacts, get_artifact, recommend_composition, resolve_binding). Scenarios 1A/1B are standard Copilot with workspace files only — rely solely on the files in that workspace directory.

Generate output into /poc/scenarios/<scenario>/poc-results/<model_name>/ directory.
```

### Scenario 2 — extended prompt

Scenario 2 uses the same base prompt with registry-specific additions. Open Copilot Chat in VS Code and select the **DRY Reuse** agent before sending — no context files need to be attached.

```
I need a trailing-90-day ARPAC (Average Revenue per Active Customer) metric for executive reporting. Deliver a reusable ARPAC metric definition that other executive dashboards can adopt.
- Reuse existing definitions, datasets, or functions where appropriate, and explain what was reused.
- ARPAC = net recognized revenue in USD (numerator) divided by the number of active customers (denominator).
- Denominator = the distinct count of active customers, using the active-customer definition aligned with the one currently used in other executive dashboards.
- Numerator = net recognized revenue in USD over the trailing 90 days, counting ONLY revenue from the customers in the denominator. Revenue from non-active customers is excluded.

Constraints:
- Do NOT read, reference, or use anything from poc/scenarios/scenario-2/expected-output/.
- Do NOT read poc/poc-architecture.md, poc/demo/walkthrough.md, or any other documentation file. Derive artifact identity, authority and bindings from what the registry tools return, not from documentation.
- Do NOT read poc/scenarios/scenario-2/registry-manifests/ directly — query the registry through the MCP tools only.
- DO read a resolved binding's `source` file under poc/scenarios/scenario-2/workspace/ to confirm exact column names, parameters and function signatures before you reference them — this is the binding's implementation source, NOT the registry-manifests/ directory. Never guess a signature; if a source file cannot be read, mark those identifiers UNCONFIRMED.
- Generate output into poc/scenarios/scenario-2/poc-results/<model_name>/ directory.
```

---

## Scenario 1A — Standard Copilot, DWH tables only

**Workspace exposed:** `poc/scenarios/scenario-1a/workspace/` — the shared DWH base tables only
(`dim_customers`, `fact_invoices`, `fact_refunds`).

**What the models do.** With no domain logic visible, every tested model generates ARPAC from
first principles straight from the raw base tables. The SQL runs and looks correct, but silently
re-derives three governed rules:

- Billable-event assembly (invoices ∪ refunds, signed amounts) — owned by `finance.datasets.fact_billable_events.v1`
- Refund netting + recognition — owned by `finance.logic.recognize_revenue.v1`
- Currency normalization — owned by `finance.logic.normalize_currency.v1`

And uses the **wrong active-customer definition**: `dim_customers.is_active` is a 12-month
operational order flag, not the certified 90-day commercial-activity status
(`sales.datasets.commercial_customer_status_90d.v1`). Nothing detects this — the duplicate
reaches review or production as new "original" code.

This is the whitepaper's *"AI assistant as duplication amplifier."* Two dashboards now show two
different ARPAC numbers, and no pipeline fails.

**Results:** `poc/scenarios/scenario-1a/poc-results/<model_name>/`

---

## Scenario 1B — Standard Copilot, domain repositories included

**Workspace exposed:** `poc/scenarios/scenario-1b/workspace/` — base DWH tables **plus** the
Finance and Marketing domain repositories.

**What the models do.** With domain code visible, models find similar artifacts through workspace
search. However, *availability and similarity do not imply authority*:

- The Finance workspace contains `invoice_revenue.sql` — a **retired** view that skips refunds.
  Models may reuse it, reproducing a known data-quality defect.
- The Marketing workspace contains an active-customer rule based on login activity — a
  **domain-local** definition not certified for executive reporting.
- The certified recognition UDF (`FINANCE.LOGIC.RECOGNIZE_REVENUE`) and billable-events table
  (`FINANCE.DATASETS.FACT_BILLABLE_EVENTS`) exist only as deployed warehouse objects, invisible
  to workspace search.

**Results:** `poc/scenarios/scenario-1b/poc-results/<model_name>/`

### Why workspace similarity alone is not enough

The scan.py harness makes the gap concrete — the same comparison engine that powers registry
lookups, running without governance metadata:

```powershell
cd poc/workspace-similarity
python scan.py --query ../demo/arpac-authoring-scratch.sql
```

```
Workspace similarity search for arpac-authoring-scratch.sql (method=ast)

  Ranked by SIMILARITY ONLY — no lifecycle, ownership or canonical status:

    0.32  [PARTIAL_REIMPLEMENTATION]  poc\scenarios\scenario-2\workspace\finance\datasets\fact_billable_events.sql
          ast=0.30 feat=0.39 | authority: UNKNOWN
    0.23  [INSUFFICIENT_EVIDENCE]  poc\scenarios\scenario-2\workspace\finance\logic\normalize_currency.sql
          ast=0.24 feat=0.19 | authority: UNKNOWN
    0.18  [INSUFFICIENT_EVIDENCE]  poc\scenarios\scenario-2\workspace\finance\datasets\invoice_revenue.sql
          ast=0.16 feat=0.24 | authority: UNKNOWN
    0.13  [PARTIAL_REIMPLEMENTATION]  poc\scenarios\scenario-2\workspace\finance\logic\recognize_revenue.sql
          ast=0.08 feat=0.32 | authority: UNKNOWN
    ...
  ⚠ The top match may be a certified canonical, a local copy, or a test fixture —
    this method cannot tell. That authority gap is what the registry closes (Scenario 2).

  Coverage caveats:
    - Warehouse objects (UDFs, tables, views) were not searched.
    - Semantic-layer / metric runtimes were not searched.
    - Repositories not checked out into this workspace were not searched.
    - Package versions not installed locally were not searched.
    - No governance signal: lifecycle, ownership and reuse intent are UNKNOWN.
```

The three gaps the whitepaper names:

1. **No authority.** Similarity rank does not distinguish certified from retired. `invoice_revenue`
   carries `lifecycle: retired` in the registry — invisible to workspace search.
2. **Workspace-bounded.** The `FINANCE.LOGIC.RECOGNIZE_REVENUE` UDF and `FACT_BILLABLE_EVENTS`
   table exist only as deployed warehouse objects and are not visible to workspace search.
3. **Similarity ≠ semantics.** The active-customer divergence (`dim_customers.is_active`, a 12-month
   flag, vs the certified 90-day status) barely registers as a structural signal, yet it is the
   most consequential error.

---

## Scenario 2 — Registry-aware authoring

**Tooling:** the **DRY Reuse** custom agent
([`.github/agents/dry-reuse.agent.md`](../../.github/agents/dry-reuse.agent.md)) connected to the
local MCP server. The agent treats the prompt as **business intent** and works through four stages:
**Discover → Resolve → Compose → Verify.**

The same base prompt works for Scenario 2 — no component list is added. The agent decomposes the
ARPAC formula already in the prompt (`net recognized revenue` ÷ `active customers`) into its
components itself, searches each concept, and resolves it to the **enterprise-wide certified**
definition — domain-local canonicals and raw base tables are not selected for this executive
request. The agent instructions prohibit inventing a composition the engineer did not ask for; it
decomposes only what the stated ARPAC definition contains.

To start: open Copilot Chat in VS Code and select the **DRY Reuse** agent.

**Setup — run once from a PowerShell terminal (not Copilot Chat):**

```powershell
# 1. Navigate to the registry package
cd poc/registry

# 2. Install dependencies (mcp is pinned to 1.x in pyproject.toml)
pip install -e ".[sql,mcp]"

# 3. Populate the SQLite store the MCP server reads from
#    --db must come before the subcommand; run from poc\registry so $pwd resolves correctly
python -m dry_registry.cli --db "$pwd\.dry_registry.sqlite" ingest
# Expected: "Ingested 9 registered artifacts ... into ...\poc\registry\.dry_registry.sqlite"
```

Then in VS Code:
- **Ctrl+Shift+P** → type `reload` → **Developer: Reload Window**
- Open Copilot Chat → tools panel → click **Update Tools** under `dry-registry`
- Expected: individual tools appear (`search_artifacts`, `recommend_composition`, etc.)

> **Why ingest is required:** the MCP server reads from `poc/registry/.dry_registry.sqlite`
> (set by `DRY_DB` in `.vscode/mcp.json`). That file does not exist until `ingest` is run —
> the server does not read the YAML manifests directly. If the store is missing or empty, all
> MCP tool calls return no results.
>
> **Re-run ingest only** if you change a manifest YAML. For repeated prompt runs with no
> manifest changes, the existing store is valid.

### Stage 1 — Discover: is there already a certified ARPAC?

The first MCP call is always `search_artifacts`. The equivalent CLI command:

```powershell
python -m dry_registry.cli search arpac --interface semantic_contract
```

ARPAC does not yet exist as a governed metric — the engineer is cleared to build it. The input
registry holds only the logical + dataset building blocks; `enterprise.semantic.arpac_90d.v1` is
what this exercise *generates*.

### Stage 2 — Discover: map components to certified artifacts

Two options are implemented. The agent uses **Option B** as the primary call.

**Option A — `find_composable_artifacts`**  
Runs a separate registry search per concept and returns the enterprise-wide canonical for each.
Does not resolve bindings.

**Option B — `recommend_composition`** (primary)

```powershell
python -m dry_registry.cli recommend "ARPAC" --component "net recognized revenue" --component "active customers"
```

```
Composition recommendation for 'ARPAC':

  reuse  net recognized revenue → finance.logic.recognize_revenue.v1 [certified]
         binding: warehouse/snowflake prod: FINANCE.LOGIC.RECOGNIZE_REVENUE
  reuse  active customers       → sales.datasets.commercial_customer_status_90d.v1 [certified]
         binding: databricks/databricks prod: sales.datasets.commercial_customer_status_90d

  Reuse 2 registered component(s); author only the 0 missing part(s) and the small composition that joins them.
```

The component terms are the two nouns in the ARPAC formula — the agent derives them from the
prompt, they are not supplied as a hint. `recommend_composition` performs in one call: a
whole-request search, a separate search per component, and per component it resolves the
**enterprise-wide certified** definition (the domain-canonical `fact_billable_events` and the
`dim_customers` base table are deliberately **not** selected for this executive metric), binding
resolution, gap identification, and a summary. It produces a **reuse plan** — not SQL. Code
generation is Copilot's responsibility.

### Stage 3 — Resolve: physical bindings per runtime

The registry treats each artifact as a logical identity with potentially multiple physical
implementations. `resolve_binding` selects the right one for the target runtime:

```powershell
python -m dry_registry.cli resolve-binding sales.datasets.commercial_customer_status_90d.v1 --runtime databricks
python -m dry_registry.cli resolve-binding finance.logic.recognize_revenue.v1 --runtime dbt
```

```
Binding resolution for sales.datasets.commercial_customer_status_90d.v1 (runtime=databricks, dialect=None):

  ► recommended: databricks/databricks prod: sales.datasets.commercial_customer_status_90d (view)

Binding resolution for finance.logic.recognize_revenue.v1 (runtime=dbt, dialect=None):

  ► recommended: dbt/snowflake prod: dry_finance_macros.recognized_revenue_relation (macro)
  alternatives:
    - warehouse/snowflake prod: FINANCE.LOGIC.RECOGNIZE_REVENUE
```

The result carries authority the workspace never had: lifecycle state, owner, reuse intent, and
the recommended physical object per engine. Revenue resolves to Snowflake (UDF or dbt macro); the
active-customer status resolves to a Databricks view — two engines, one registry query.

`recognize_revenue` is one certified identity with two Snowflake-stack bindings: the native UDF
and a dbt macro. A dbt model reuses it with `{{ recognized_revenue_relation(...) }}`; a raw-SQL
author calls the UDF. Both reference the *same* governed logic; neither is flagged as duplication.

### Stage 4 — Compose: write only the missing derived logic

Once discovery and binding resolution are complete, **Copilot generates the composition**. There
is no implemented composition engine — `recommend_composition` creates a plan, and Copilot fills
in the code. The agent instructions say: *"Only then help write the small piece of new, derived
code that is genuinely missing."*

For ARPAC, that is:

```
finance.logic.recognize_revenue.v1        (Snowflake)
        +
sales.datasets.commercial_customer_status_90d.v1   (Databricks)
        ↓
enterprise.datasets.customer_arpac_components_90d  ← authored here
        ↓
enterprise.semantic.arpac_90d                      ← authored here
```

The active-customer status resolves only to a **Databricks** view, while the enterprise target
engine is **Snowflake** — `resolve_binding(..., runtime=warehouse)` returns no Snowflake binding.
The agent does **not** fabricate a bridge object: it references the resolved Databricks binding
under an explicit "assumes reachable from Snowflake once a binding is provisioned" precondition, and
flags provisioning that binding (portable-SQL framework, or a shared/federated view registered as an
additional binding) as an integration requirement. The cross-engine join is materialized once in the
governed components dataset. The ARPAC ratio is the only genuinely new logic. Reference outputs:
[`../scenarios/scenario-2/expected-output/customer_arpac_components_90d.sql`](../scenarios/scenario-2/expected-output/customer_arpac_components_90d.sql),
[`../scenarios/scenario-2/expected-output/arpac_90d.sql`](../scenarios/scenario-2/expected-output/arpac_90d.sql).

### Stage 5 — Verify: no duplication

After Copilot creates or edits the composition, the engineer selects the generated code in Copilot
Chat and runs:

```
/compare-with-registry
```

This calls `compare_code` against the registry scope. The equivalent CLI call demonstrates what it
flags on the **from-scratch draft** (re-deriving from raw base tables instead of calling the
certified UDF):

```powershell
python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql --scope registry
```

```
Comparison for arpac-authoring-scratch.sql (scope=registry, method=ast):

  [PARTIAL_REIMPLEMENTATION] finance.datasets.fact_billable_events.v1
      ast=0.27 feat=0.39 (combined=0.30) | authority: REGISTERED_CANONICAL | lifecycle: certified
      shared: fact_invoices, fact_refunds, invoice_events, refund_events, amount, currency, customer, invoice, net, recogniz, refund, revenue
      → Overlaps a registered artifact (certified); reuse the shared parts rather than copying logic.
  [INSUFFICIENT_EVIDENCE] finance.logic.normalize_currency.v1
      ast=0.24 feat=0.13 (combined=0.21) | authority: REGISTERED_CANONICAL | lifecycle: shared
      shared: amount, currency, exchange, fx
      → No strong match; safe to author, but register the new artifact.
  [INSUFFICIENT_EVIDENCE] finance.datasets.invoice_revenue.v1
      ast=0.16 feat=0.24 (combined=0.18) | authority: REGISTERED_CANONICAL | lifecycle: retired
      shared: fact_invoices, amount, currency, customer, fx, invoice, recogniz, refund, revenue
      → No strong match; safe to author, but register the new artifact.
  [PARTIAL_REIMPLEMENTATION] finance.logic.recognize_revenue.v1
      ast=0.08 feat=0.33 (combined=0.13) | authority: REGISTERED_CANONICAL | lifecycle: certified
      shared: amount, currency, customer, fx, invoice, net, netting, recogniz, refund, revenue
      → Overlaps a registered artifact (certified); reuse the shared parts rather than copying logic.
  [INSUFFICIENT_EVIDENCE] sales.datasets.commercial_customer_status_90d.v1
      ast=0.08 feat=0.18 (combined=0.10) | authority: REGISTERED_CANONICAL | lifecycle: certified
      shared: dim_customers, active, customer, invoice, order
      → No strong match; safe to author, but register the new artifact.

  Closest match: finance.datasets.fact_billable_events.v1 [PARTIAL_REIMPLEMENTATION] — Overlaps a registered artifact (certified) ...
```

A correctly-composed output that references the certified bindings rather than re-deriving from
base tables returns no `PARTIAL_REIMPLEMENTATION` flags.

### Impact analysis (optional)

Before promoting a change to any building block, check who breaks:

```powershell
python -m dry_registry.cli impact finance.logic.recognize_revenue.v1
```

```
Impact analysis for finance.logic.recognize_revenue.v1 [certified]

  Depends on (upstream):
    - finance.datasets.fact_billable_events.v1 (source_input)
    - finance.logic.normalize_currency.v1 (transformation_dependency)
  Consumed by (downstream — would break on an incompatible change):
    - (no registered downstream dependents — ARPAC is what this exercise adds)
```

**Result:** no revenue logic, no netting rule, no currency rule, and no activity window is
re-implemented. Reuse of the canonical artifacts is the lowest-friction path — the whitepaper's
*"AI assistant as reuse accelerator."*

---

## CLI quick reference

All commands run from `poc/registry`, fully offline.

```powershell
pip install -e ".[sql]"                # add ,vector for embeddings; ,mcp for the MCP server

# CLI-only (uses ~/.dry_registry.sqlite):
python -m dry_registry.cli ingest
# For MCP use, write to the path mcp.json expects:
python -m dry_registry.cli --db "$pwd\.dry_registry.sqlite" ingest

python -m dry_registry.cli search "recognize revenue"
python -m dry_registry.cli recommend "ARPAC" --component "net recognized revenue" --component "active customers"
python -m dry_registry.cli resolve-binding finance.logic.recognize_revenue.v1 --runtime dbt
python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql --scope registry
python -m dry_registry.cli impact finance.logic.recognize_revenue.v1

# workspace similarity harness (similarity without authority):
python ../workspace-similarity/scan.py --query ../demo/arpac-authoring-scratch.sql
```

Add `--json` to any command to get the raw structured payload the MCP tools also return.

---

## Side-by-side summary

| | Scenario 1A | Scenario 1B | Scenario 2 |
|---|---|---|---|
| Workspace visible | DWH base tables only | Base tables + domain repos | DRY Artifact Registry (MCP) |
| Finds similar code | ✗ | ✓ (workspace only) | ✓ (whole platform) |
| Knows which is **canonical/certified** | ✗ | ✗ | ✓ |
| Sees warehouse-only / other-repo artifacts | ✗ | ✗ | ✓ |
| Distinguishes reuse from duplication (bindings) | ✗ | ✗ | ✓ |
| Impact analysis before change | ✗ | ✗ | ✓ |
| Net effect on ARPAC | divergent, undetected | maybe reused, unverified | canonical by composition |
