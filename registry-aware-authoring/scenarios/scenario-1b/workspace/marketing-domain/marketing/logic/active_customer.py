# marketing/logic/active_customer.py

from pyspark.sql import DataFrame, functions as F


def active_customer(
    customer_logins: DataFrame,
    as_of_date: str,
    trailing_days: int = 90,
) -> DataFrame:
    """Return the distinct customers considered active.

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
