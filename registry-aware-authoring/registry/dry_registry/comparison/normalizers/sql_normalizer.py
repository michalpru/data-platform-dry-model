"""SQL normalization for structural comparison.

Dialect-aware when sqlglot is installed (parses with the source dialect and re-emits a
canonical form); falls back to a regex/whitespace normalizer otherwise. This is the single
home of SQL normalization — every scorer routes through here.

The result is an "AST/parser-normalized token sequence": comments, Jinja, casing and layout
are removed so copy-paste and near-identical rewrites collapse together. It is NOT a full
semantic-equivalence or tree-edit comparison.
"""

from __future__ import annotations

import logging
import re

try:  # optional, recommended (still fully offline)
    import sqlglot

    logging.getLogger("sqlglot").setLevel(logging.ERROR)  # silence unsupported-syntax notices
    _HAS_SQLGLOT = True
except Exception:  # pragma: no cover - depends on environment
    _HAS_SQLGLOT = False

_JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)
_LINE_COMMENT = re.compile(r"--[^\n]*")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_DOLLAR_BODY = re.compile(r"\$\$(.*?)\$\$", re.DOTALL)
_WS = re.compile(r"\s+")


def _unwrap_udf_body(text: str) -> str:
    """CREATE FUNCTION ... $$ body $$  ->  fingerprint the body (the real logic)."""
    m = _DOLLAR_BODY.search(text)
    return m.group(1) if m else text


def normalize_sql(text: str, dialect: str | None = None) -> str:
    text = _unwrap_udf_body(text)
    text = _JINJA.sub(" ", text)
    text = _BLOCK_COMMENT.sub(" ", text)
    text = _LINE_COMMENT.sub(" ", text)
    if _HAS_SQLGLOT:
        try:
            parsed = [
                stmt.sql(normalize=True, pretty=False, comments=False)
                for stmt in sqlglot.parse(text, read=dialect or None)
                if stmt is not None
            ]
            if parsed:
                text = " ".join(parsed)
        except Exception:
            pass  # fall back to regex normalization
    text = text.lower()
    return _WS.sub(" ", text).strip()
