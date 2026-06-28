# Enterprise tier (certified cross-domain semantics)

This layer contains **certified semantic and dataset artifacts whose scope spans the entire organization** — definitions that must be consistent across all domain teams and appear in cross-domain executive reporting.

## Why a separate tier?

The `domains/` layer is the right home for domain-specific logic that may evolve independently.  
Enterprise artifacts **cannot** evolve independently — a change to how "Active Customer" is counted affects every domain that reports on it, every executive dashboard that compares customer numbers, and every ML model trained on that signal.

The enterprise tier makes that dependency explicit and governable.

## Ownership model

Enterprise-tier artifacts are owned by the **Data Governance function** (CDO office, data governance team, or equivalent authority).  
Domain teams are **consumers**, not owners.  
Proposals for new versions require a formal compatibility review and approval by the governance owner.

## Examples in this repo

| FQN | Kind | Description |
|---|---|---|
| `enterprise.semantics.customer.v1` | SemanticModel | Enterprise Customer entity — shared grain + dimensions |
| `enterprise.metrics.active_customer.v1` | Metric | Certified Active Customer definition (90-day window) |
| `enterprise.reporting.customer.v1` | DatasetContract | Certified Customer master dataset interface |

## Connection to the article

The **"Active Customer" divergence problem** described in Part 1 is solved here:

- Marketing previously defined Active Customer as "logged in within 30 days" — embedded in SQL views.
- Finance used their own window, embedded in BI calculations.
- Executive dashboards diverged.

**The fix:**
1. `enterprise.metrics.active_customer.v1` — certified 90-day window, owned by governance.
2. Both `domains/marketing/` and `domains/finance/` reference `enterprise.semantics.customer.v1` as the base entity.
3. Marketing may keep a domain-local 30-day metric for campaign targeting, but it is labeled `lifecycle: local` — not for cross-domain comparison.

## Where enterprise artifacts are registered

`platform/registry/registered/enterprise.reporting.customer.v1.yaml`
