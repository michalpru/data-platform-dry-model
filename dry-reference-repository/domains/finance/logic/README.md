# Finance callable logic (DRY in Code / DRY in Logic)

Finance-owned **callable logic** artifacts that encode revenue business rules once and are
reused by transformation models and Spark pipelines. These are published to the DRY Artifact
Registry so consumers resolve the canonical definition instead of re-deriving it.

| FQN | Interface | Kind | Lifecycle | Bindings |
|---|---|---|---|---|
| `finance.logic.recognize_revenue.v1` | callable_logic | table-valued SQL UDF **+** PySpark function | certified | `analytics.finance.fn_recognize_revenue` (warehouse), `finance_revenue.recognition.recognize_revenue` (spark package) |
| `finance.logic.normalize_reporting_currency.v1` | callable_logic | SQL macro | shared | `dry_finance_macros.normalize_reporting_currency` (macro symbol) |

## Why two bindings for `recognize_revenue`

The revenue-recognition rule (orders→invoices mapping + netting) must be identical whether it
runs in the warehouse (SQL UDF) or in a Spark pipeline. Both physical objects are registered as
**Implementation Bindings of one logical identity**. This is the registry mechanism that
distinguishes *"the same governed definition on two engines"* from *"two duplicate
implementations"* — the exact ambiguity Portability M0 caused in the whitepaper worked example,
where Finance rebuilt the revenue UDF on a different vendor warehouse.

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
