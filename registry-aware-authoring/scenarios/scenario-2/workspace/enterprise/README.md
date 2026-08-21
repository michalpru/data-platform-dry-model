# Enterprise Analytics — authoring target (Snowflake)

This is the **empty target workspace** for Scenario 2. The DRY Reuse agent authors the two new
Enterprise Analytics artifacts here, on top of certified artifacts resolved from the registry:

- `enterprise/datasets/customer_arpac_components_90d.sql` — the cross-engine composition
  (Finance recognized revenue on Snowflake + Sales active-customer status on Databricks).
- `enterprise/semantic/arpac_90d.sql` — the trailing-90-day ARPAC metric.

During the live demo these folders start empty; generated results are written to
`../../../../poc-results/<model_name>/` and must NOT be exposed in the authoring workspace.
