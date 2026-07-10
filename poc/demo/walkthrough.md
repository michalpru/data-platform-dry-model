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

The three patterns map directly to the whitepaper's *Duplication Detection and Prevention
Techniques* table (§4.3.3): Pattern 1 has no detection, Pattern 2 is **workspace similarity
search** (low–medium confidence, informative only), Pattern 3 is **registry-backed canonical
resolution** (high confidence, prevention at authoring time).

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
python scan.py --query ../demo/arpac-authoring-scratch.sql --method ast
```

```
Workspace similarity search for arpac-authoring-scratch.sql (method=ast)

  Ranked by SIMILARITY ONLY — no lifecycle, ownership, or canonical status:

    0.66  dry-reference-repository\domains\finance\logic\udfs\finance.logic.recognize_revenue.v1.sql
    0.15  dry-reference-repository\domains\finance\logic\macros\finance.logic.normalize_reporting_currency.v1.sql
    0.07  dry-reference-repository\domains\finance\datasets\finance.marts.revenue_events.v1.sql
    0.07  dry-reference-repository\platform\packages\sql\dry_shared_macros\macros\with_boolean_flag.sql
    0.03  dry-reference-repository\domains\marketing\datasets\marketing.marts.active_customers_30d.v1.sql
    ...
  ⚠ The top match may be a certified canonical, a local copy, or a test fixture —
    this method cannot tell. That authority gap is what the registry closes (Pattern 3).
```

**What worked:** the search *did* surface the certified recognition UDF as the top structural
match (0.66). Accidental re-implementation is now less likely.

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

### The pluggable "3 models" comparison

The whitepaper lists three detection techniques for Pattern 2 (structural fingerprinting,
embedding-based similarity, LLM-based analysis). This harness ships the **AST baseline** and makes
the other two pluggable:

```powershell
# Structural / AST (default, offline, deterministic)
python scan.py --query ../demo/arpac-authoring-scratch.sql --method ast

# Embedding-based (optional local model; pip install -e "../registry[vector]")
python scan.py --query ../demo/arpac-authoring-scratch.sql --method embedding
```

Add an LLM backend by implementing one `score()` method in
[`../registry/dry_registry/similarity.py`](../registry/dry_registry/similarity.py). All three
share the same normalization, so scores are comparable. The point of the comparison is not which
model wins, but that **all three return similarity, none returns authority.**

---

## Pattern 3 — WITH the DRY Artifact Registry

**Setup.** The assistant is connected to the registry (via an MCP server or IDE extension in a
real deployment; via the CLI here). Authoring now starts with resolution, not generation.

### Step 1 — Is there already a certified ARPAC?

```powershell
python -m dry_registry.cli search arpac --interface semantic_contract
```

At the true start of authoring there is nothing certified to reuse — ARPAC does not yet exist as a
governed metric, so the engineer is cleared to build it. (In this snapshot the finished
`finance.metrics.arpac.v1` is already registered as the *shared candidate* outcome of this very
exercise.)

### Step 2 — Resolve the certified building blocks

```powershell
python -m dry_registry.cli resolve revenue
python -m dry_registry.cli resolve active_customer
```

```
Canonical resolution for 'active_customer':

  ► enterprise.metrics.active_customer.v1  [CERTIFIED]
      Active Customer — owned by data-governance
      interface: semantic_contract | scope:

      → Reuse this artifact instead of re-implementing it.
```

Unlike Pattern 2, this answer carries **authority**: lifecycle state (`CERTIFIED`), owner
(`data-governance`), interface type, Implementation Bindings, and declared dependencies. The
engineer now knows *which* definition is the canonical one and how to reference it.

### Step 3 — Detect the re-implementation before it merges

If the engineer (or the assistant) drafts the from-scratch version anyway, the registry compares
it to **registered** artifacts and attaches governance authority to the match:

```powershell
python -m dry_registry.cli duplicates ../demo/arpac-authoring-scratch.sql --interface callable_logic --lang sql
```

```
Duplication check for arpac-authoring-scratch.sql (method=ast):

  [HIGH] score=0.66  finance.logic.recognize_revenue.v1  [certified] via analytics.finance.fn_recognize_revenue
  [HIGH] score=0.66  finance.logic.recognize_revenue.v1  [certified] via analytics_uat.finance.fn_recognize_revenue
  [HIGH] score=0.66  finance.logic.recognize_revenue.v1  [certified] via finance_revenue.recognition.recognize_revenue
  [     ] score=0.15  finance.logic.normalize_reporting_currency.v1  [shared] via dry_finance_macros.normalize_reporting_currency

  ⚠ Likely reimplementation of a governed artifact:
    finance.logic.recognize_revenue.v1 [certified] owned by finance-analytics
    → Route to review / reuse the canonical artifact instead of merging this.
```

Note the same logical artifact matched via **three Implementation Bindings** (two warehouse
environments + the Spark package). The registry knows they are one governed definition, so
reusing the Spark binding in a Spark pipeline is *not* flagged as duplication — only the
re-derivation from raw tables is.

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
