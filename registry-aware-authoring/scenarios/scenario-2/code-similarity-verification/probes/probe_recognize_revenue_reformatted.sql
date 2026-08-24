-- PROBE (normalization robustness, reformat-only): the CERTIFIED
-- finance.logic.recognize_revenue rule copied VERBATIM except for cosmetics —
-- comments stripped, keywords lower-cased, whitespace/indentation reflowed, blank lines
-- removed. No identifier is renamed. Expectation: SQL normalization collapses the cosmetic
-- differences and the AST/structural signal against the certified artifact is high enough to
-- rank it #1 as a near-copy (a formatter-only "new file" that is really the certified rule).
create or replace function FINANCE.LOGIC.RECOGNIZE_REVENUE(P_START_DATE date, P_END_DATE date)
returns table (CUSTOMER_ID number(38,0), BILLABLE_EVENT_ID varchar, RECOGNITION_DATE date, EVENT_TYPE varchar, SOURCE_CURRENCY varchar, RECOGNIZED_REVENUE_USD number(18,2))
language sql as $$
select b.CUSTOMER_ID, b.BILLABLE_EVENT_ID, b.RECOGNITION_DATE, b.EVENT_TYPE, b.CURRENCY_CODE as SOURCE_CURRENCY, fx.CONVERTED_AMOUNT as RECOGNIZED_REVENUE_USD
from FINANCE.DATASETS.FACT_BILLABLE_EVENTS as b, lateral table(FINANCE.LOGIC.NORMALIZE_CURRENCY(b.NET_AMOUNT, b.CURRENCY_CODE, 'USD', b.RECOGNITION_DATE)) as fx
where b.RECOGNITION_DATE between P_START_DATE and P_END_DATE and b.IS_RECOGNIZABLE = TRUE
$$;
