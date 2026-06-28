"""Marketing domain ingestion example.

The Marketing team owns the campaign source mapping, token provider, and record extraction.
It reuses the same platform ingestion module used by Finance instead of rebuilding
pagination and response handling for another source API.
"""

from dry_platform_utils.ingestion import RestIngestionConfig, ingest_rest_pages  # type: ignore[import-not-found]


def ingest_campaign_members(http_get, token_provider):
    config = RestIngestionConfig(
        base_url="https://campaigns.example.internal",
        endpoint="/v2/members",
        headers={"Authorization": f"Bearer {token_provider()}"},
        page_param="cursor",
        page_size_param="limit",
    )

    return ingest_rest_pages(
        http_get=http_get,
        config=config,
        extract_records=lambda response: response["members"],
        has_next_page=lambda response: bool(response.get("next_cursor")),
        classify_error=lambda exc: "retryable" if "timeout" in str(exc).lower() else "fatal",
    )