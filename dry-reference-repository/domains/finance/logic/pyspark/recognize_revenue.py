"""finance.logic.recognize_revenue.v1 — PySpark Implementation Binding.

Same logical identity as the warehouse table-valued UDF
``analytics.finance.fn_recognize_revenue`` (see ../udfs/finance.logic.recognize_revenue.v1.sql).
This binding realizes the *identical* orders->invoices mapping and netting rule for the
Spark runtime, so a Spark pipeline reuses the canonical revenue-recognition logic instead
of rebuilding it. Registering both physical objects under one FQN is what lets the registry
answer "these are the same definition, on two engines" rather than treating them as duplicates.

Business rules (must stay in sync with the SQL binding):
  1. Orders -> Invoices mapping: revenue exists only for invoiced orders.
  2. Netting: net_amount = gross - sum(refunds/credit notes), in source currency.
Currency normalization is applied downstream (finance.logic.normalize_reporting_currency.v1),
so this function is currency-agnostic.
"""

from pyspark.sql import DataFrame
from pyspark.sql import functions as F


def recognize_revenue(
    orders: DataFrame,
    invoices: DataFrame,
    refunds: DataFrame,
    start_date: str,
    end_date: str,
) -> DataFrame:
    """Return canonical revenue events for the given date range.

    Output columns match the SQL UDF: revenue_event_id, customer_id, event_date,
    source_currency, gross_amount, netting_amount, net_amount, recognition_status.
    """
    invoiced = (
        invoices.alias("i")
        .join(orders.alias("o"), F.col("i.order_id") == F.col("o.order_id"))
        .where(F.col("i.invoice_date").between(start_date, end_date))
        .select(
            F.col("i.invoice_id").alias("revenue_event_id"),
            F.col("o.customer_id").alias("customer_id"),
            F.col("i.invoice_date").alias("event_date"),
            F.col("i.currency").alias("source_currency"),
            F.col("i.amount").alias("gross_amount"),
            F.when(F.col("i.status") == "settled", F.lit("recognized"))
            .otherwise(F.lit("pending"))
            .alias("recognition_status"),
        )
    )

    netting = refunds.groupBy("invoice_id").agg(
        F.sum("amount").alias("netting_amount")
    )

    return (
        invoiced.join(
            netting,
            invoiced["revenue_event_id"] == netting["invoice_id"],
            "left",
        )
        .withColumn("netting_amount", F.coalesce(F.col("netting_amount"), F.lit(0)))
        .withColumn("net_amount", F.col("gross_amount") - F.col("netting_amount"))
        .drop("invoice_id")
    )
