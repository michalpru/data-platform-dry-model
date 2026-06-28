# Python wheel: `dry-platform-utils`

This is an example of a **buildable, versioned** platform package.

How reuse happens:
- Platform CI builds a wheel and publishes it to internal PyPI.
- Domain repos declare a dependency (see `domains/*/dependencies/requirements.txt`).
- Engineers import utilities instead of copying files.

This is how DRY in Code becomes dependency-based rather than coordination-based.

## Included examples

- `dry_platform_utils.ingestion.ingest_rest_pages` — reusable REST ingestion loop for pagination, retry, response extraction, and error classification.
	Finance and Marketing provide source-specific endpoints, token providers, extraction functions, and error classifiers, but both reuse the same tested control flow.
- `dry_platform_utils.transforms.with_boolean_flag` — reusable flag helper. Domains supply the business condition.

This mirrors the article's `ingest_*.py` failure pattern: each source API differs, but OAuth setup, pagination, retry, response handling, and error classification should not be reimplemented independently by every team.
