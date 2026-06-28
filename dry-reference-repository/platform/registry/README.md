# DRY Artifact Registry (example)

This folder demonstrates what a minimal registry might store.

- `registered/` — declared shared/certified artifacts
- `observed/` — discovered runtime objects from warehouse catalogs, DAGs, query logs, or semantic telemetry

The registry is a control plane used for measurement and enforcement, not a full data catalog.

## How a team checks “is this already covered?”

In real platforms, the registry is usually queryable (API/UI). In this reference repo, treat
`platform/registry/registered/` as the registry’s source-of-truth snapshot.

Practical workflows:

- Search by FQN (preferred):
	- Example FQN: `finance.reporting.revenue_events.v1`
- Search by concept keywords (advisory):
	- `revenue_events`, `active_customer`, `completed_orders`

If you find a near-match but not an exact match, treat it as a **duplication hotspot** signal:
- either reuse the existing artifact (default)
- or justify divergence and register a new artifact with a different FQN + compatibility intent

## Registered vs observed

| Registry area | Source | Purpose |
|---|---|---|
| `registered/` | YAML manifests merged from platform, enterprise, and domain repos | Authoritative declarations of shared/certified reuse interfaces |
| `observed/` | Warehouse catalogs, orchestration metadata, BI metadata, query logs | Runtime evidence used to detect bypasses, shadow tables, and duplication hotspots |

Observed objects do not automatically become registered artifacts. They are evidence for review: either map the object to an existing registered artifact, retire it, or promote it through the normal lifecycle.
