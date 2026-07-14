"""Normalization entry point shared by fingerprinting and every scorer.

`normalize()` returns (language, normalized_text). Language detection is a cheap heuristic
overridable with an explicit hint. SQL normalization is dialect-aware; Python is not.
"""

from __future__ import annotations

from typing import Tuple

from .python_normalizer import normalize_python
from .sql_normalizer import normalize_sql


def detect_lang(text: str, hint: str = "") -> str:
    if hint in ("sql", "python"):
        return hint
    stripped = text.lstrip()
    if stripped.startswith(("def ", "import ", "from ", '"""', "#", "@")):
        return "python"
    return "sql"


def normalize(text: str, lang_hint: str = "", dialect: str | None = None) -> Tuple[str, str]:
    lang = detect_lang(text, lang_hint)
    if lang == "python":
        return lang, normalize_python(text)
    return lang, normalize_sql(text, dialect=dialect)


__all__ = ["normalize", "detect_lang", "normalize_sql", "normalize_python"]
