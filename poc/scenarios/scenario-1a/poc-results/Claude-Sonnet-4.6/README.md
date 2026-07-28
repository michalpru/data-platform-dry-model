# ARPAC Trailing-90-Day Metric — PoC Result

**Model:** Claude Sonnet 4.6  
**Scenario:** 1-A — trailing-90-day ARPAC for executive reporting  
**Platform:** Snowflake SQL  

---

## Output file

| File | Purpose |
|------|---------|
| `metric_arpac_trailing_90d.sql` | Queryable SQL implementation of the ARPAC metric |

---

## What was reused (and why)

### 1. `shared.dim_customers.is_active` — active-customer definition
- **Reused as-is.** No new active-customer logic was invented.
- The column comment states: *"placed ≥ 1 order in the last 12 months"*.
- Because the requirement asks for the ARPAC denominator to be **aligned with other executive dashboards**, the `is_active` flag is the correct join point — other dashboards already drive off this column, so the definition is consistent by construction.

### 2. `shared.fact_invoices` — gross revenue source
- **Reused with filters** (`invoice_status = 'POSTED'`, `invoice_date` in trailing window, `currency_code = 'USD'`).
- The status vocabulary (`POSTED / DRAFT / VOID`) is taken directly from the DDL; only `POSTED` rows represent recognized revenue.

### 3. `shared.fact_refunds` — refund/credit-note adjustments
- **Reused with filters** (`refund_status = 'APPROVED'`, joined back to `fact_invoices` to keep the same 90-day window).
- The DDL comment explicitly states: *"net recognized revenue must subtract approved refunds/credit notes from gross invoice amounts"* — so the join and subtraction pattern follows the documented intent of this table.

---

## Design decisions

| Decision | Rationale |
|----------|-----------|
| **Denominator = `COUNT(*) WHERE is_active = TRUE`** | Reuses the executive-dashboard definition verbatim; no additional 90-day filter on the denominator, which matches how dashboards typically present "active customers as of today". |
| **Refund scoping: by `invoice_date`** | Refunds are subtracted only if their source invoice falls in the trailing window. This makes the numerator self-consistent: gross and net adjustments both refer to the same invoice cohort. |
| **NULL guard on `ARPAC`** | Returns `NULL` (not zero) when there are no active customers, to avoid a divide-by-zero and to signal a data-quality issue rather than a meaningful zero. |
| **`COALESCE(..., 0)` on revenue CTEs** | Prevents `NULL` propagation when there are no rows in the window (e.g., start of data load). |
| **Currency: USD only** | `fact_invoices` notes that currency is NOT necessarily USD. No FX-rate table exists in this workspace. Filtering to `currency_code = 'USD'` is the safe default; a TODO comment in the SQL flags where to add FX conversion. |

---

## Limitations / follow-up needed

1. **Multi-currency support**: The implementation only counts USD-denominated invoices and refunds. To include non-USD revenue, an FX-rates lookup table (spot rate or period-average) must be added to `shared` and joined in the `gross_revenue` and `approved_refunds` CTEs.

2. **Active-customer window vs. denominator window**: The `is_active` flag is computed on a rolling 12-month basis outside this query. If the flag is not refreshed daily, the denominator may be slightly stale relative to the 90-day numerator window. Ensure the ETL that populates `dim_customers.is_active` runs before this metric is queried.

3. **Refund timing**: Refunds are scoped by `invoice_date` of the source invoice, not by `refund_date`. If the business requires cash-basis refund recognition (subtract a refund in the period it was issued, regardless of original invoice date), replace the `fi.invoice_date` filter with `fr.refund_date >= DATEADD('day', -90, CURRENT_DATE)`.
