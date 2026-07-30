def with_boolean_flag(df, flag_name: str, condition):
    """Attach a boolean flag column based on a condition.

    This is intentionally business-agnostic (DRY in Code). It encodes *how* to attach a flag,
    not *what* the flag means.

    The concrete execution engine (PySpark, Snowpark, pandas) determines the condition type.
    """
    return df.withColumn(flag_name, condition)
