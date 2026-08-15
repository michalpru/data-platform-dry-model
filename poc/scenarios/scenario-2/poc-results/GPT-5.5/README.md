# Trailing 90 Day ARPAC

This directory defines a reusable executive ARPAC metric:

`ARPAC = net recognized revenue in USD over the trailing 90 days / distinct active customers`

The numerator is restricted to customers in the denominator, so revenue from non-active customers is excluded.

## Registry Reuse

- Reused `sales.datasets.commercial_customer_status_90d.v1` for the denominator because the registry describes it as the certified Sales-owned active-customer definition used by executive dashboards. Resolved binding: `sales.datasets.commercial_customer_status_90d` on Databricks.
- Reused `finance.logic.recognize_revenue.v1` for the numerator because the registry describes it as the certified Finance-owned net recognized revenue USD definition used by executive dashboards. Resolved dbt binding: `dry_finance_macros.recognized_revenue_relation` on Snowflake.
- Did not reuse `finance.datasets.invoice_revenue.v1` because the registry marks it retired and superseded by the certified recognized-revenue path.

## Cross-Engine Note

The registry did not return an ANSI SQL binding for either required component. The active-customer component is bound on Databricks, while recognized revenue is bound on Snowflake/dbt. The SQL therefore references the resolved certified bindings and assumes the Databricks active-customer view is reachable from the execution engine once a target-engine binding or governed federation path is provisioned.

## Contract Confirmation Gap

The registry source paths for the resolved bindings could not be opened from the workspace locations available to this run, so column names and the dbt macro signature that depend on those source files are labeled `UNCONFIRMED` in `arpac_trailing_90d_components.sql`.