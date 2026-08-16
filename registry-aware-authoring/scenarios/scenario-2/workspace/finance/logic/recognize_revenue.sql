-- finance.logic.recognize_revenue  (Snowflake SQL table function)
-- =========================================================================
-- Registry FQN: finance.logic.recognize_revenue.v1  (callable logic)
-- Owner: finance-analytics | Lifecycle: certified
--
-- Certified Finance revenue-recognition rule. Reads the canonical billable-event stream
-- FINANCE.DATASETS.FACT_BILLABLE_EVENTS (do NOT re-derive it from raw invoices/refunds), keeps
-- only recognizable events in the requested window, and normalizes each signed amount to USD via
-- the certified finance.logic.normalize_currency function. Refund/credit-note netting is already
-- carried in the billable event's signed NET_AMOUNT.
--
-- ONE logical identity, TWO Snowflake-stack bindings: this native UDF and a dbt macro
-- (finance/logic/dbt/recognized_revenue_relation.sql) that reuses the exact same rule inside dbt.
-- =========================================================================
CREATE OR REPLACE FUNCTION FINANCE.LOGIC.RECOGNIZE_REVENUE(
    P_START_DATE DATE,
    P_END_DATE   DATE
)
RETURNS TABLE (
    CUSTOMER_ID             NUMBER(38, 0),
    BILLABLE_EVENT_ID       VARCHAR,
    RECOGNITION_DATE        DATE,
    EVENT_TYPE              VARCHAR,
    SOURCE_CURRENCY         VARCHAR,
    RECOGNIZED_REVENUE_USD  NUMBER(18, 2)
)
LANGUAGE SQL
AS
$$
    SELECT
        b.CUSTOMER_ID,
        b.BILLABLE_EVENT_ID,
        b.RECOGNITION_DATE,
        b.EVENT_TYPE,
        b.CURRENCY_CODE AS SOURCE_CURRENCY,
        fx.CONVERTED_AMOUNT AS RECOGNIZED_REVENUE_USD
    FROM FINANCE.DATASETS.FACT_BILLABLE_EVENTS AS b,
    LATERAL TABLE(
        FINANCE.LOGIC.NORMALIZE_CURRENCY(
            b.NET_AMOUNT,
            b.CURRENCY_CODE,
            'USD',
            b.RECOGNITION_DATE
        )
    ) AS fx
    WHERE b.RECOGNITION_DATE BETWEEN P_START_DATE AND P_END_DATE
      AND b.IS_RECOGNIZABLE = TRUE
$$;
