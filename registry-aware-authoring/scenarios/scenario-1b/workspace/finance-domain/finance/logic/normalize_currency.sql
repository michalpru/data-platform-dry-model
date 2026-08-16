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
