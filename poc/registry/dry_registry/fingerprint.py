"""Structural fingerprinting for SQL and Python (compatibility shim).

Normalization now lives in `comparison.normalizers` (the single shared home). This module
keeps the historical `normalize()` / `fingerprint()` API used by the Pattern-2 harness and
existing tests, delegating to that core.

The similarity these fingerprints drive is "AST/parser-normalized token-sequence similarity":
comments, Jinja, casing and layout are removed so copy-paste and near-identical rewrites
collapse together. It is NOT a full semantic-equivalence or tree-edit comparison.
"""

from __future__ import annotations

import hashlib
from typing import Tuple

from .comparison.normalizers import normalize  # re-exported for back-compat


def fingerprint(text: str, lang_hint: str = "") -> Tuple[str, str, str]:
    """Return (language, normalized_text, sha1_hash)."""
    lang, norm = normalize(text, lang_hint)
    digest = hashlib.sha1(norm.encode("utf-8")).hexdigest()
    return lang, norm, digest


__all__ = ["normalize", "fingerprint"]
