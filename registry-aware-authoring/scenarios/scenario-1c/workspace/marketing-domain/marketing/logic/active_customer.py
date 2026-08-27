from pyspark.sql import DataFrame, functions as F


def active_customer(
    customer_logins: DataFrame,
    as_of_date: str,
    trailing_days: int = 90,
) -> DataFrame:
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
