from dataclasses import dataclass, field
from time import sleep
from typing import Any, Callable, Iterable, Mapping


@dataclass(frozen=True)
class RestIngestionConfig:
    """Business-agnostic REST ingestion configuration.

    Source-specific concerns such as endpoint paths, token providers, and record extraction
    are injected by the domain. Retry, pagination, and error classification remain shared.
    """

    base_url: str
    endpoint: str
    page_param: str = "page"
    page_size_param: str = "page_size"
    page_size: int = 500
    max_pages: int = 100
    max_retries: int = 3
    retry_backoff_seconds: float = 1.0
    headers: Mapping[str, str] = field(default_factory=dict)


def ingest_rest_pages(
    http_get: Callable[..., Mapping[str, Any]],
    config: RestIngestionConfig,
    extract_records: Callable[[Mapping[str, Any]], Iterable[Mapping[str, Any]]],
    has_next_page: Callable[[Mapping[str, Any]], bool],
    classify_error: Callable[[Exception], str] | None = None,
) -> list[Mapping[str, Any]]:
    """Ingest paginated REST records using a reusable control-flow skeleton.

    This is DRY in Code: authentication headers, pagination parameters, response parsing,
    and error classification can vary by source, but every domain uses the same tested
    ingestion loop for pagination, retry, and error handling.
    """

    records: list[Mapping[str, Any]] = []

    for page in range(1, config.max_pages + 1):
        for attempt in range(1, config.max_retries + 1):
            try:
                response = http_get(
                    f"{config.base_url.rstrip('/')}/{config.endpoint.lstrip('/')}",
                    headers=config.headers,
                    params={
                        config.page_param: page,
                        config.page_size_param: config.page_size,
                    },
                )
                break
            except Exception as exc:
                error_class = classify_error(exc) if classify_error else "retryable"
                if error_class != "retryable" or attempt == config.max_retries:
                    raise
                sleep(config.retry_backoff_seconds * attempt)

        records.extend(extract_records(response))

        if not has_next_page(response):
            break

    return records