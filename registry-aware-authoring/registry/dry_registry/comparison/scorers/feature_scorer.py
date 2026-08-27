"""Language-neutral feature-overlap scoring (works across languages).

Jaccard similarity over the two transformation profiles' feature sets. This is the signal
that lets a PySpark implementation and a SQL UDF of the same rule look related even though
their AST token streams are incomparable.
"""

from __future__ import annotations

from typing import List, Tuple

from ..features import TransformationProfile


def feature_score(a: TransformationProfile, b: TransformationProfile) -> float:
    fa, fb = a.feature_set(), b.feature_set()
    if not fa or not fb:
        return 0.0
    inter = fa & fb
    union = fa | fb
    return len(inter) / len(union) if union else 0.0


def shared_features(a: TransformationProfile, b: TransformationProfile) -> Tuple[List[str], List[str], List[str]]:
    """Return (shared source entities, shared operations, shared concepts) for evidence."""
    shared = a.feature_set() & b.feature_set()
    src = sorted(f.split(":", 1)[1] for f in shared if f.startswith("src:"))
    ops = sorted(f.split(":", 1)[1] for f in shared if f.startswith(("agg:", "grp:", "joins:")))
    concepts = sorted(f.split(":", 1)[1] for f in shared if f.startswith("concept:"))
    return src, ops, concepts
