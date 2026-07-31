-- finance.logic.normalize_currency  (Snowflake SQL table function)
-- =========================================================================
-- Registry FQN: finance.logic.normalize_currency.v1  (callable logic)
-- Owner: finance-analytics | Lifecycle: shared
--
-- Currency rule: convert an amount from its source currency to a target (reporting) currency
-- using the daily FX rate as-of the conversion date. Amounts already in the target currency pass
-- through at rate 1.0. Centralizing this rule prevents each team from hardcoding its own FX table,
-- join grain, or rounding convention. This is the Snowflake binding of the logical identity; a dbt
-- macro binding (finance/logic/dbt/normalize_currency.sql) exposes the same rule inside dbt.
-- =========================================================================
CREATE OR REPLACE FUNCTION FINANCE.LOGIC.NORMALIZE_CURRENCY(
    P_AMOUNT              NUMBER(18, 2),
    P_SOURCE_CURRENCY     VARCHAR,
    P_TARGET_CURRENCY     VARCHAR,
    P_CONVERSION_DATE     DATE
)
RETURNS TABLE (
    ORIGINAL_AMOUNT       NUMBER(18, 2),
    SOURCE_CURRENCY       VARCHAR,
    TARGET_CURRENCY       VARCHAR,
    CONVERSION_DATE       DATE,
    EXCHANGE_RATE         NUMBER(18, 8),
    CONVERTED_AMOUNT      NUMBER(18, 2)
)
LANGUAGE SQL
AS
$$
    SELECT
        P_AMOUNT,
        P_SOURCE_CURRENCY,
        P_TARGET_CURRENCY,
        P_CONVERSION_DATE,
        CASE
            WHEN P_SOURCE_CURRENCY = P_TARGET_CURRENCY
                THEN 1::NUMBER(18, 8)
            ELSE fx.EXCHANGE_RATE
        END AS EXCHANGE_RATE,
        ROUND(
            P_AMOUNT *
            CASE
                WHEN P_SOURCE_CURRENCY = P_TARGET_CURRENCY THEN 1
                ELSE fx.EXCHANGE_RATE
            END,
            2
        )::NUMBER(18, 2) AS CONVERTED_AMOUNT
    FROM (SELECT 1 AS DUMMY) AS seed
    LEFT JOIN FINANCE.DATASETS.DIM_EXCHANGE_RATES AS fx
        ON fx.FROM_CURRENCY = P_SOURCE_CURRENCY
       AND fx.TO_CURRENCY = P_TARGET_CURRENCY
       AND fx.RATE_DATE = P_CONVERSION_DATE
    WHERE P_SOURCE_CURRENCY = P_TARGET_CURRENCY
       OR fx.EXCHANGE_RATE IS NOT NULL
$$;
