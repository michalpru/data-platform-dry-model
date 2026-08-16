"""AST / parser-normalized token-sequence similarity (same-language only).

Both snippets are normalized (SQL via sqlglot/regex, Python via ast.dump) and scored with
difflib's token ratio. High confidence for direct / near-identical matches; it does NOT
prove semantic equivalence. Cross-language pairs are unsupported and return None.
"""

from __future__ import annotations

import difflib
from typing import Optional

from ..normalizers import detect_lang, normalize


def ast_score(
    a: str,
    b: str,
    lang_a: str = "",
    lang_b: str = "",
    dialect_a: str | None = None,
    dialect_b: str | None = None,
) -> Optional[float]:
    la = detect_lang(a, lang_a)
    lb = detect_lang(b, lang_b)
    if la != lb:
        return None  # SQL-to-Python AST comparison is unsupported.
    _, na = normalize(a, la, dialect=dialect_a)
    _, nb = normalize(b, lb, dialect=dialect_b)
    if not na or not nb:
        return 0.0
    return difflib.SequenceMatcher(None, na.split(), nb.split()).ratio()
