# Scenario 2 — Registry-aware authoring

**Workspace exposed to Copilot:** the **DRY Artifact Registry**, reached through the thin MCP server and the **DRY Reuse** custom agent (or the CLI). Unlike scenarios 1A/1B, authoring starts with **resolution**, not generation.

The governed artifacts this scenario resolves against are the **pure-YAML** manifests in
[`registry-manifests/`](registry-manifests/) (`shared/` base tables plus `domains/finance/` and
`domains/sales/` and `domains/marketing/`). The registry holds no code; each binding's `source` points into
[`workspace/`](workspace/), the mocked repositories where the real implementations live. The
`workspace/enterprise/` tree is the **empty authoring target** the agent writes into.

The agent searches by **intent**, checks lifecycle/ownership, resolves bindings across engines (a
Snowflake UDF for revenue, a Databricks view for active status), rejects the retired
`invoice_revenue` and the two registered domain-local look-alikes, and authors **only** the missing
ARPAC composition — nothing governed is re-implemented. The cross-engine gap (no Snowflake binding
for the Databricks active-customer view) is *surfaced*, not faked.

The [`code-similarity-verification/`](code-similarity-verification/) folder holds recorded
`compare_code` controls proving the detector fires on real duplication and stays quiet on
correctly-composed reuse.

- **Architecture (registry service + comparison service + MCP + agent):** [`../../README.md`](../../README.md) (§7)
- **Setup & narrated run with real output:** [`../../demo-walkthrough.md`](../../demo-walkthrough.md) (Scenario 2)
- **Recorded results & scoring:** [`../../poc-results.md`](../../poc-results.md)
- **Raw model outputs:** [`poc-results/`](poc-results/)
