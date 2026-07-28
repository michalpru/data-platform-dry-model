-- finance.normalize_currency — shared currency-normalization logic (finance domain repo: Snowflake)
-- Snowflake SQL (table-valued function).
-- =========================================================================
-- Registry lifecycle: SHARED. A business-agnostic utility that converts an amount from a
-- source currency to a target currency using the exchange-rate table. It is consumed by both
-- the legacy invoice_revenue view and the certified recognize_revenue logic.
--
-- Implemented here as a Snowflake table-valued function. The registry records the per-runtime
-- bindings (this Snowflake TVF, plus a Databricks SQL UDF for Spark consumers).
-- =========================================================================
CREATE OR REPLACE FUNCTION finance.normalize_currency(
    amount           NUMBER(18,2),
    source_currency  VARCHAR,
    target_currency  VARCHAR,
    conversion_date  DATE
)
RETURNS TABLE (
    original_amount  NUMBER(18,2),
    source_currency  VARCHAR,
    target_currency  VARCHAR,
    exchange_rate    NUMBER(18,8),
    converted_amount NUMBER(18,2)
)
AS
$$
    SELECT
        amount                                      AS original_amount,
        source_currency,
        target_currency,
        fx.exchange_rate,
        ROUND(amount * fx.exchange_rate, 2)         AS converted_amount
    FROM finance.dim_exchange_rates AS fx
    WHERE fx.from_currency = source_currency
      AND fx.to_currency   = target_currency
      AND fx.rate_date     = conversion_date
$$;
