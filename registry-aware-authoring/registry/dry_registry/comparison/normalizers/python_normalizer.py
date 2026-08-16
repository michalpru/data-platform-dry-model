"""Python / PySpark normalization for structural comparison.

Uses the stdlib `ast` module so formatting, comments and line numbers are ignored. The
normalized form is the `ast.dump` token stream — the Python analogue of the SQL
parser-normalized token sequence.
"""

from __future__ import annotations

import ast
import re

_WS = re.compile(r"\s+")


def normalize_python(text: str) -> str:
    try:
        tree = ast.parse(text)
        return _WS.sub(" ", ast.dump(tree, annotate_fields=False)).strip()
    except SyntaxError:
        return _WS.sub(" ", text.lower()).strip()
