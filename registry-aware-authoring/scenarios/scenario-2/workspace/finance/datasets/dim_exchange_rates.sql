-- finance.datasets.dim_exchange_rates  (Snowflake SQL DDL)
-- Finance-owned daily exchange rates used by certified and legacy revenue implementations.
CREATE OR REPLACE TABLE FINANCE.DATASETS.DIM_EXCHANGE_RATES (
    FROM_CURRENCY    VARCHAR(3) NOT NULL,
    TO_CURRENCY      VARCHAR(3) NOT NULL,
    RATE_DATE        DATE NOT NULL,
    EXCHANGE_RATE    NUMBER(18, 8) NOT NULL,
    RATE_SOURCE      VARCHAR,

    CONSTRAINT PK_DIM_EXCHANGE_RATES
        PRIMARY KEY (
            FROM_CURRENCY,
            TO_CURRENCY,
            RATE_DATE
        )
);

COMMENT ON TABLE FINANCE.DATASETS.DIM_EXCHANGE_RATES IS
'Finance-owned daily exchange rates used by certified and legacy revenue implementations.';
