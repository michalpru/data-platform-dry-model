# Three-pattern walkthrough: authoring ARPAC

> Task: build **ARPAC = Average Revenue per Active Customer** for the executive dashboard,
> reusing enterprise-certified definitions instead of rebuilding them.
>
> All commands below run **fully offline**. Outputs shown are real (captured from the PoC).
> Run the engine first:
> ```powershell
> cd poc/registry
> pip install -e ".[sql]"      # PyYAML + sqlglot; both offline
> python -m dry_registry.cli ingest
> ```

The three patterns map to the authoring-time rows of the whitepaper's *Duplication Detection and
Prevention Techniques* table (§4.3.3): Pattern 1 has no detection, Pattern 2 is **workspace
similarity search** (low–medium confidence, informative only), Pattern 3 is **registry-backed
canonical resolution** (high confidence, prevention at authoring time).

> **How this PoC extends the whitepaper.** In the whitepaper, the three *detection techniques* —
> structural fingerprinting (AST), embedding-based similarity, and LLM-based analysis — sit at
> **build time**, inside the CI/CD *Duplication Detection and Prevention Flow*. This PoC brings
> those same techniques **forward to authoring time**: the AST engine that a CI gate would run
> post-hoc is the same engine powering the Pattern-2 workspace search and the Pattern-3
> `compare` check here — so a likely reimplementation surfaces while the engineer is still
> typing, not only after the PR is opened.
>
> **Two integration surfaces.** The workspace flow (Pattern 2) is **CLI-only** — similarity
> without authority. The registry flow (Pattern 3) is also available through **GitHub Copilot**
> (a custom agent over a thin MCP server) for registry-aware authoring; see the final section.

---

## Pattern 1 — No registry, no workspace search

**Setup.** The engineer opens a fresh analytics repo and asks the AI assistant to "compute
average revenue per active customer." The assistant sees only the local file context. It has no
knowledge of the certified recognition UDF, the currency macro, or the 90-day active-customer
definition. It happily generates working SQL from the raw tables.

**Result:** [`arpac-authoring-scratch.sql`](arpac-authoring-scratch.sql). It runs and looks
correct, but it silently re-implements **three governed rules** (orders→invoices mapping, netting,
currency) and invents a **30-day** active-customer window that contradicts the certified
**90-day** enterprise standard.

Nothing detects this. The duplicate reaches review — or production — as new "original" code.
This is the whitepaper's *"AI assistant as duplication amplifier."*

**Why it matters:** two dashboards now show two different ARPAC numbers, and no pipeline fails.

---

## Pattern 2 — No registry, WITH workspace similarity search

**Setup.** Same task, but now the assistant can run similarity search across the repositories
open in the workspace. The engineer either searches by keyword or, more realistically, writes a
draft and asks "is there anything like this already?"

```powershell
cd poc/workspace-similarity
python scan.py --query ../demo/arpac-authoring-scratch.sql
```

```
Workspace similarity search for arpac-authoring-scratch.sql (method=ast)

  Ranked by SIMILARITY ONLY — no lifecycle, ownership or canonical status:

    0.65  [NEAR_MATCH]  dry-reference-repository\domains\finance\logic\udfs\finance.logic.recognize_revenue.v1.sql
          ast=0.66 feat=0.62 | authority: UNKNOWN
    0.44  [PARTIAL_REIMPLEMENTATION]  dry-reference-repository\domains\finance\logic\pyspark\recognize_revenue.py
          feat=0.44 | authority: UNKNOWN
    0.15  [INSUFFICIENT_EVIDENCE]  dry-reference-repository\domains\finance\logic\macros\finance.logic.normalize_reporting_currency.v1.sql
          ast=0.15 feat=0.15 | authority: UNKNOWN
    ...
  ⚠ The top match may be a certified canonical, a local copy, or a test fixture —
    this method cannot tell. That authority gap is what the registry closes (Pattern 3).

  Coverage caveats:
    - Warehouse objects (UDFs, tables, views) were not searched.
    - Semantic-layer / metric runtimes were not searched.
    - Repositories not checked out into this workspace were not searched.
    - Package versions not installed locally were not searched.
    - No governance signal: lifecycle, ownership and reuse intent are UNKNOWN.
```

**What worked:** the search *did* surface the certified recognition rule as the top structural
match (0.65, `NEAR_MATCH`) — and even related the **PySpark** binding cross-language via the
language-neutral feature signal. Accidental re-implementation is now less likely.

**What is still missing — the three Pattern-2 gaps the whitepaper names:**

1. **No authority.** The ranking is by similarity, not governance. The engineer cannot tell that
   the 0.66 match is *certified and owned by finance-analytics*, while the 0.03 match
   (`marketing.marts.active_customers_30d`) is an intentionally-local 30-day variant that must
   **not** be reused for executive reporting.
2. **Workspace-bounded.** Only code open in the workspace is visible. Artifacts realized only as
   **warehouse objects** (the `fn_recognize_revenue` UDF deployed to Snowflake, the
   `revenue_events` table) or living in **other teams' repos** are invisible to the scan.
3. **Similarity ≠ semantics.** The active-customer divergence (30d vs 90d) barely registers as a
   structural signal, yet it is the most consequential error.

### Bringing the CI/CD detection techniques to authoring time

The whitepaper places three detection techniques — **structural fingerprinting (AST)**,
**embedding-based similarity**, and **LLM-based analysis** — at **build time**, in the CI/CD flow.
This PoC runs those same techniques *at authoring time* as the engine behind the workspace search.
The harness is now a thin wrapper over the shared **Comparison service** (`scope="workspace"`), so
the AST baseline, the language-neutral feature signal and the optional embedding tier are the
**same code** the registry scope uses:

```powershell
# Structural + feature (default, offline, deterministic)
python scan.py --query ../demo/arpac-authoring-scratch.sql

# Add the on-demand embedding tier (optional local model; pip install -e "../registry[vector]")
python scan.py --query ../demo/arpac-authoring-scratch.sql --embeddings
```

The **LLM tier stays in Copilot**: the service returns structured evidence (signals + shared
entities/operations), and the model explains and decides. The point of the comparison is not
which signal wins, but that **all of them return similarity, none returns authority.**

---

## Pattern 3 — WITH the DRY Artifact Registry

**Setup.** The assistant is connected to the registry (via the CLI here, or via the MCP server +
Copilot agent in the final section). Authoring now starts with resolution, not generation.

### Step 1 — Is there already a certified ARPAC?

```powershell
python -m dry_registry.cli search arpac --interface semantic_contract
```

At the true start of authoring there is nothing certified to reuse — ARPAC does not yet exist as a
governed metric, so the engineer is cleared to build it. (In this snapshot the finished
`finance.metrics.arpac.v1` is already registered as the *shared candidate* outcome of this very
exercise.)

### Step 2 — Resolve the certified building blocks and their bindings

```powershell
python -m dry_registry.cli resolve "active customer"
python -m dry_registry.cli resolve-binding finance.logic.recognize_revenue.v1 --runtime spark
```

```
Canonical resolution for 'active customer':

  ► enterprise.metrics.active_customer.v1  [CERTIFIED]
      Active Customer — owned by data-governance
      reuse intent: UNKNOWN

      → Reuse this artifact instead of re-implementing it.

Binding resolution for finance.logic.recognize_revenue.v1 (runtime=spark, dialect=None):

  ► recommended: spark/spark prod: finance_revenue.recognition.recognize_revenue (function)
  alternatives:
    - warehouse/snowflake prod: analytics.finance.fn_recognize_revenue
    - warehouse/snowflake uat: analytics_uat.finance.fn_recognize_revenue
```

Unlike Pattern 2, this answer carries **authority**: lifecycle state (`CERTIFIED`), owner
(`data-governance`), and the **recommended physical binding for the engineer's runtime** — the
Spark function for a Spark pipeline, with the warehouse UDFs offered as alternatives. The engineer
now knows *which* definition is canonical and exactly how to reference it.

### Step 3 — Detect the re-implementation before it merges

If the engineer (or the assistant) drafts the from-scratch version anyway, the registry compares
it to **registered** artifacts and attaches governance authority + evidence to the match:

```powershell
python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql --scope registry
```

```
Comparison for arpac-authoring-scratch.sql (scope=registry, method=ast):

  [NEAR_MATCH] finance.logic.recognize_revenue.v1
      ast=0.66 feat=0.42 (combined=0.61) | authority: REGISTERED_CANONICAL | lifecycle: certified
      shared: amount, credit, currency, customer, gross, invoice, net, netting, order, recogniz, refund, reporting, revenue
      → Very likely a re-implementation of the registered artifact (certified); review and reuse it.
  [INSUFFICIENT_EVIDENCE] finance.logic.normalize_reporting_currency.v1
      ast=0.15 feat=0.15 (combined=0.15) | authority: REGISTERED_CANONICAL | lifecycle: shared
      shared: fx_rates, amount, currency, fx, reporting
      → No strong match; safe to author, but register the new artifact.

  Closest match: finance.logic.recognize_revenue.v1 [NEAR_MATCH] — Very likely a re-implementation ...
```

### Step 4 — Compose, and check impact

ARPAC is authored by composition (see
[`../../dry-reference-repository/domains/finance/semantics/metrics/finance.metrics.arpac.v1.yaml`](../../dry-reference-repository/domains/finance/semantics/metrics/finance.metrics.arpac.v1.yaml)):
numerator `finance.metrics.net_recognized_revenue.v1`, denominator
`enterprise.metrics.active_customer.v1`. Before promoting a change to any building block, impact
analysis shows who breaks:

```powershell
python -m dry_registry.cli impact finance.logic.recognize_revenue.v1
```

```
Impact analysis for finance.logic.recognize_revenue.v1 [certified]

  Depends on (upstream):
    - finance.raw.orders.v1 (source_input)
    - finance.raw.invoices.v1 (source_input)
    - finance.raw.refunds.v1 (source_input)
  Consumed by (downstream — would break on an incompatible change):
    - finance.reporting.revenue_events.v1 (transformation_dependency)
```

**Result:** no revenue logic, no netting rule, no currency rule, and no activity window is
re-implemented. Reuse of the canonical artifact is the lowest-friction path — the whitepaper's
*"AI assistant as reuse accelerator."*

> **Comparison returns logical artifacts, not bindings.** `recognize_revenue` has three physical
> implementations (two warehouse envs + a Spark package), but the comparison reports it **once**
> as a single logical identity. `resolve_binding` then picks the physical object for the
> engineer's runtime. Reusing the Spark binding in a Spark pipeline is therefore *not* flagged as
> duplication — only the re-derivation from raw tables is.

---

## Registry-aware authoring through GitHub Copilot (Scenario C)

Everything above runs from the CLI. The same registry scope is also available *inside the IDE* so
the engineer never leaves the editor. This path uses a **thin MCP server** (a proxy over the
Lookup & Compare Service) and a **Copilot custom agent** — no business logic is duplicated.

```powershell
cd poc/registry
pip install -e ".[sql,mcp]"          # add ,vector for the on-demand embedding tier
python -m dry_registry.cli ingest    # build the control plane once
```

Reload VS Code so [`.vscode/mcp.json`](../../.vscode/mcp.json) starts the `dry-registry` server,
open Copilot Chat, and select the **DRY Reuse** agent
([`.github/agents/dry-reuse.agent.md`](../../.github/agents/dry-reuse.agent.md)). Two workflows:

- **`/search-registry`** (intent-first) — the engineer describes what they want to build. The
  agent calls `search_artifacts`; if there is no single match it decomposes the request and calls
  `find_composable_artifacts`, then `resolve_binding` for each component before writing any
  reference. *ARPAC example:* search "ARPAC" → absent → search "net recognized revenue" and
  "active customer" separately → resolve bindings → write only the ratio.
- **`/compare-with-registry`** (code-first) — the engineer has code selected. The agent calls
  `compare_code`, reads the relationship label + shared entities, explains *why* it matches, and
  recommends reuse or registration.

The division of responsibility is deliberate:

> **Registry** knows what exists · **Comparison service** knows what is similar ·
> **AI (Copilot)** knows how to help the engineer use both.

The MCP tools (`search_artifacts`, `get_artifact`, `find_composable_artifacts`, `resolve_binding`,
`compare_code`) return the *same structured JSON* the CLI's `--json` flag prints. The model is
taught the **workflow and the tools**, never the registry contents — and the Python services
**never call an LLM**. The LLM reasoning stays in Copilot, acting on the evidence the services
return.

---

## Side-by-side summary

| | Pattern 1 | Pattern 2 | Pattern 3 |
|---|---|---|---|
| Finds similar code | ✗ | ✓ (workspace only) | ✓ (whole platform) |
| Knows which is **canonical/certified** | ✗ | ✗ | ✓ |
| Sees warehouse-only / other-repo artifacts | ✗ | ✗ | ✓ |
| Distinguishes reuse from duplication (bindings) | ✗ | ✗ | ✓ |
| Impact analysis before change | ✗ | ✗ | ✓ |
| Net effect on ARPAC | divergent, undetected | maybe reused, unverified | canonical by composition |
