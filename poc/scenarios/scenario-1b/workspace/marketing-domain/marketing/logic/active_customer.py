# marketing/logic/active_customer.py
"""Marketing-specific definition of an active customer.

Registry lifecycle: SHARED (marketing-owned). This encodes a MARKETING rule — a customer is
"active" if they logged into the Marketing Portal at least once within the trailing window. It
is NOT the enterprise commercial-activity definition, and must NOT be used for executive ARPAC.

It is included to demonstrate a Pattern-2 failure mode: it is discoverable and looks reusable,
but reusing it silently substitutes a marketing engagement rule for the certified 90-day
commercial-activity definition (enterprise.metrics.active_customer.v1).
"""

import pandas as pd


def active_customer(
    customer_logins: pd.DataFrame,
    as_of_date: str,
    trailing_days: int = 90,
) -> pd.DataFrame:
    """Return the distinct customers Marketing considers active.

    Parameters
    ----------
    customer_logins : DataFrame
        Expected columns: customer_id, login_timestamp, application_name.
    as_of_date : str
        Reporting date (YYYY-MM-DD).
    trailing_days : int
        Number of trailing days to evaluate.
    """
    as_of = pd.Timestamp(as_of_date)
    window_start = as_of - pd.Timedelta(days=trailing_days)

    active = customer_logins[
        (customer_logins["application_name"] == "Marketing Portal")
        & (customer_logins["login_timestamp"] >= window_start)
        & (customer_logins["login_timestamp"] <= as_of)
    ]

    return active[["customer_id"]].drop_duplicates().reset_index(drop=True)
