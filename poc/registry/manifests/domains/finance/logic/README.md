# Finance callable logic (DRY in Code / DRY in Logic)

Finance-owned **callable logic** artifacts that encode revenue business rules once and are
reused by transformation models (raw SQL and dbt). These are published to the DRY Artifact
Registry so consumers resolve the canonical definition instead of re-deriving it.

| FQN | Interface | Kind | Lifecycle | Bindings |
|---|---|---|---|---|
| `finance.logic.recognize_revenue.v1` | callable_logic | Snowflake SQL UDF **+** dbt macro | certified | `analytics.finance.fn_recognize_revenue` (warehouse UDF), `dry_finance_macros.recognize_revenue` (dbt macro) |
| `finance.logic.normalize_reporting_currency.v1` | callable_logic | dbt SQL macro | shared | `dry_finance_macros.normalize_reporting_currency` (dbt macro) |

## Why two bindings for `recognize_revenue`

The revenue-recognition rule (orders→invoices mapping + netting) must be identical whether a
consumer calls it as a native warehouse **SQL UDF** or reuses it inside a **dbt** project via the
macro. Both physical objects are registered as **Implementation Bindings of one logical identity**.
This is the registry mechanism that distinguishes *"the same governed definition, reused through
two surfaces"* from *"two duplicate implementations"*. dbt already solves reuse *inside* dbt; the
registry additionally records that the dbt macro and the UDF are the **same certified capability**,
and spans the runtimes dbt never sees (semantic layers, notebooks, other engines).

## Composition

```
finance.reporting.revenue_events.v1  (queryable dataset)
  └── FROM TABLE( fn_recognize_revenue(...) )         -- finance.logic.recognize_revenue.v1
  └── normalize_reporting_currency(net_amount, ...)   -- finance.logic.normalize_reporting_currency.v1
  └── with_boolean_flag(recognition_status = ...)     -- platform.callable.dry_shared_macros.v1
  └── JOIN enterprise.reporting.customer.v1           -- canonical customer entity
```

Currency normalization is deliberately kept **out** of the recognition UDF so the UDF stays
currency-agnostic and reusable; the model composes the two.
