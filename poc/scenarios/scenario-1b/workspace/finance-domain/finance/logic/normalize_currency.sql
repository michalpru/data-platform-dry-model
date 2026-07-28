-- finance.normalize_currency — shared currency-normalization logic (finance domain repo)
-- ANSI SQL.
-- =========================================================================
-- Registry lifecycle: SHARED. A business-agnostic utility that converts an amount from a
-- source currency to a target currency using the exchange-rate table. It is consumed by both
-- the legacy invoice_revenue view and the certified recognize_revenue logic.
--
-- Expressed here as a portable ANSI query template (bind :amount, :source_currency,
-- :target_currency, :conversion_date). The registry records the per-runtime bindings
-- (e.g. a Snowflake table-valued function, a Databricks SQL UDF).
-- =========================================================================
SELECT
    src.amount                                      AS original_amount,
    src.source_currency,
    src.target_currency,
    fx.exchange_rate,
    ROUND(src.amount * fx.exchange_rate, 2)         AS converted_amount
FROM (
    SELECT
        CAST(:amount          AS DECIMAL(18,2)) AS amount,
        CAST(:source_currency AS VARCHAR(3))    AS source_currency,
        CAST(:target_currency AS VARCHAR(3))    AS target_currency,
        CAST(:conversion_date AS DATE)          AS conversion_date
) AS src
JOIN finance.dim_exchange_rates AS fx
  ON fx.from_currency = src.source_currency
 AND fx.to_currency   = src.target_currency
 AND fx.rate_date     = src.conversion_date;
