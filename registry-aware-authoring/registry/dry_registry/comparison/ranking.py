"""Combine independent similarity signals into a single ranking score.

Priority: a strong same-language AST match dominates (high confidence). When AST is
unavailable (cross-language) or weak, the language-neutral feature/embedding signal drives
the ordering. Kept intentionally simple and explainable.
"""

from __future__ import annotations

from ..models import SimilaritySignals


def combined_score(sig: SimilaritySignals) -> float:
    ast = sig.ast
    neutral = max(v for v in (sig.feature or 0.0, sig.embedding or 0.0, 0.0))
    if ast is not None:
        # Same-language: AST leads, neutral signal nudges ties.
        return round(0.8 * ast + 0.2 * neutral, 4)
    # Cross-language: neutral signal only.
    return round(neutral, 4)
