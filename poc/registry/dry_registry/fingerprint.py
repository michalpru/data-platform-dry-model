"""Structural fingerprinting for SQL and Python (AST baseline).

Design goals for the PoC:
  - Deterministic and fully offline (stdlib only).
  - SQL: use sqlglot to parse and canonicalize when available; otherwise fall back to a
    regex/whitespace normalizer. Both strip comments, Jinja, aliases-noise, and casing so
    copy-paste and near-identical reimplementations collapse to the same fingerprint.
  - Python: use the stdlib `ast` module (ast.dump) so formatting and comments are ignored.

This mirrors the whitepaper's "Structural fingerprinting (AST)" technique: high confidence
for direct / near-identical matches; it does not catch arbitrary semantically-equivalent
rewrites (that is the advisory embedding/LLM tier).
"""

from __future__ import annotations

import ast
import hashlib
import re
from typing import Tuple

try:  # optional, recommended
    import sqlglot

    _HAS_SQLGLOT = True
except Exception:  # pragma: no cover - depends on environment
    _HAS_SQLGLOT = False


_JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)
_LINE_COMMENT = re.compile(r"--[^\n]*")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_DOLLAR_BODY = re.compile(r"\$\$(.*?)\$\$", re.DOTALL)
_WS = re.compile(r"\s+")


def _detect_lang(text: str, hint: str = "") -> str:
    if hint in ("sql", "python"):
        return hint
    stripped = text.lstrip()
    if stripped.startswith(("def ", "import ", "from ", '"""', "#")):
        return "python"
    return "sql"


def _unwrap_udf_body(text: str) -> str:
    """If SQL is a CREATE FUNCTION ... $$ body $$, fingerprint the body (the real logic)."""
    m = _DOLLAR_BODY.search(text)
    return m.group(1) if m else text


def _normalize_sql(text: str) -> str:
    text = _unwrap_udf_body(text)
    text = _JINJA.sub(" ", text)
    text = _BLOCK_COMMENT.sub(" ", text)
    text = _LINE_COMMENT.sub(" ", text)
    if _HAS_SQLGLOT:
        try:
            parsed = [
                stmt.sql(normalize=True, pretty=False, comments=False)
                for stmt in sqlglot.parse(text)
                if stmt is not None
            ]
            if parsed:
                text = " ".join(parsed)
        except Exception:
            pass  # fall back to regex normalization
    text = text.lower()
    text = _WS.sub(" ", text).strip()
    return text


def _normalize_python(text: str) -> str:
    try:
        tree = ast.parse(text)
        # ast.dump without attributes ignores formatting, comments, line numbers.
        return _WS.sub(" ", ast.dump(tree, annotate_fields=False)).strip()
    except SyntaxError:
        return _WS.sub(" ", text.lower()).strip()


def normalize(text: str, lang_hint: str = "") -> Tuple[str, str]:
    """Return (language, normalized_text)."""
    lang = _detect_lang(text, lang_hint)
    if lang == "python":
        return lang, _normalize_python(text)
    return lang, _normalize_sql(text)


def fingerprint(text: str, lang_hint: str = "") -> Tuple[str, str, str]:
    """Return (language, normalized_text, sha1_hash)."""
    lang, norm = normalize(text, lang_hint)
    digest = hashlib.sha1(norm.encode("utf-8")).hexdigest()
    return lang, norm, digest
