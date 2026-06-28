"""Finance domain ingestion example.

The Finance team owns the billing source mapping, token provider, and record extraction.
It reuses dry_platform_utils.ingestion for the generic REST pagination loop.
"""

from dry_platform_utils.ingestion import RestIngestionConfig, ingest_rest_pages  # type: ignore[import-not-found]


def ingest_billing_accounts(http_get, token_provider):
    config = RestIngestionConfig(
        base_url="https://billing.example.internal",
        endpoint="/v1/accounts",
        headers={"Authorization": f"Bearer {token_provider()}"},
        page_param="page",
        page_size_param="limit",
    )

    return ingest_rest_pages(
        http_get=http_get,
        config=config,
        extract_records=lambda response: response["accounts"],
        has_next_page=lambda response: response.get("next_page") is not None,
        classify_error=lambda exc: "retryable" if "429" in str(exc) else "fatal",
    )