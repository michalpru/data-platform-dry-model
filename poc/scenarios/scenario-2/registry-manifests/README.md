# Scenario 2 — Registry manifests (logical metadata index)

These are the **pure YAML `DryArtifact` manifests** that make up the DRY Artifact Registry for the
Scenario 2 demo. The registry stores **only definitions and bindings — never code**. Each
Implementation Binding's `source` points to the real code in the sibling mocked workspace
([../workspace/](../workspace/)), which the comparison engine reads to fingerprint.

Layout:

- `shared/` — foundational base tables (`dim_customers`, `fact_invoices`, `fact_refunds`,
  `dim_exchange_rates`).
- `domains/finance/` — finance datasets (`fact_billable_events`, retired `invoice_revenue`) and
  callable logic (`normalize_currency`, `recognize_revenue`).
- `domains/sales/` — the Sales-owned Databricks `commercial_customer_status_90d` view.

The engine loads every `kind: DryArtifact` manifest under this tree recursively. Point it here with
`DRY_MANIFESTS_DIR` and the code root with `DRY_WORKSPACE_DIR` (defaults already target this
scenario).
