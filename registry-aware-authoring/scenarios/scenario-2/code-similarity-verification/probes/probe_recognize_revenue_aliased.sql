-- PROBE (normalization robustness): the CERTIFIED finance.logic.recognize_revenue rule,
-- copied and lightly disguised. Parameters renamed (P_START_DATE -> FROM_DT), table alias
-- renamed (b -> ev, fx -> cur), whitespace/reflow changed, comments stripped. Logic identical.
-- Expectation: SQL AST normalization sees through the cosmetic renames and reports high
-- structural similarity to the certified artifact (a copy-paste that must be reused, not forked).
CREATE OR REPLACE FUNCTION FINANCE.LOGIC.REVENUE_RECOGNIZED(
    FROM_DT DATE,
    TO_DT   DATE
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
    SELECT ev.CUSTOMER_ID,
           ev.BILLABLE_EVENT_ID,
           ev.RECOGNITION_DATE,
           ev.EVENT_TYPE,
           ev.CURRENCY_CODE AS SOURCE_CURRENCY,
           cur.CONVERTED_AMOUNT AS RECOGNIZED_REVENUE_USD
    FROM FINANCE.DATASETS.FACT_BILLABLE_EVENTS AS ev,
    LATERAL TABLE(
        FINANCE.LOGIC.NORMALIZE_CURRENCY(ev.NET_AMOUNT, ev.CURRENCY_CODE, 'USD', ev.RECOGNITION_DATE)
    ) AS cur
    WHERE ev.IS_RECOGNIZABLE = TRUE
      AND ev.RECOGNITION_DATE BETWEEN FROM_DT AND TO_DT
$$;
