# marketing/logic/active_customer.py
"""Marketing-specific definition of an active customer (Databricks / PySpark).

Registry lifecycle: SHARED (marketing-owned). This encodes a MARKETING rule — a customer is
"active" if they logged into the Marketing Portal at least once within the trailing window. It
is NOT the enterprise commercial-activity definition, and must NOT be used for executive ARPAC.

The marketing domain runs on Databricks; this is a PySpark job over the Spark login events. It
is included to demonstrate a Pattern-2 failure mode: it is discoverable and looks reusable, but
reusing it silently substitutes a marketing engagement rule for the certified 90-day
commercial-activity definition (enterprise.metrics.active_customer.v1) — and it lives on a
DIFFERENT engine (Databricks) than the Snowflake revenue view, so composing the two means
crossing warehouses.
"""

from pyspark.sql import DataFrame, functions as F


def active_customer(
    customer_logins: DataFrame,
    as_of_date: str,
    trailing_days: int = 90,
) -> DataFrame:
    """Return the distinct customers Marketing considers active.

    Parameters
    ----------
    customer_logins : pyspark.sql.DataFrame
        Expected columns: customer_id, login_timestamp, application_name.
    as_of_date : str
        Reporting date (YYYY-MM-DD).
    trailing_days : int
        Number of trailing days to evaluate.
    """
    as_of = F.to_date(F.lit(as_of_date))
    window_start = F.date_sub(as_of, trailing_days)

    return (
        customer_logins
        .where(F.col("application_name") == "Marketing Portal")
        .where(F.col("login_timestamp") >= window_start)
        .where(F.col("login_timestamp") <= as_of)
        .select("customer_id")
        .distinct()
    )
