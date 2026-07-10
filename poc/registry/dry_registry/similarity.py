"""Pluggable similarity backends for duplication detection.

Two tiers, matching the whitepaper's detection techniques:

  AstBackend (default, always available, offline, deterministic)
    - Normalizes both snippets with fingerprint.normalize (SQL via sqlglot/regex, Python via
      ast.dump), then scores with difflib token ratio. High confidence for direct/near matches.

  EmbeddingBackend (optional; `pip install dry-registry[vector]`)
    - Local sentence-transformers model -> cosine similarity. Fully offline once the model is
      cached. This is the advisory semantic tier used to compare Pattern-2 "3 models".
    - Selected via get_backend("embedding", model=...). Missing deps raise a clear message.

Both return a float in [0, 1]. Callers decide thresholds; nothing here blocks a build.
"""

from __future__ import annotations

import difflib
from typing import List, Optional

from .fingerprint import normalize


class SimilarityBackend:
    name = "base"

    def score(self, a: str, b: str, lang_hint: str = "") -> float:
        raise NotImplementedError

    def score_many(self, query: str, candidates: List[str], lang_hint: str = "") -> List[float]:
        return [self.score(query, c, lang_hint) for c in candidates]


class AstBackend(SimilarityBackend):
    """Structural/AST-normalized similarity via difflib token ratio."""

    name = "ast"

    def score(self, a: str, b: str, lang_hint: str = "") -> float:
        _, na = normalize(a, lang_hint)
        _, nb = normalize(b, lang_hint)
        if not na or not nb:
            return 0.0
        return difflib.SequenceMatcher(None, na.split(), nb.split()).ratio()


class EmbeddingBackend(SimilarityBackend):
    """Optional local-embedding semantic similarity (advisory only)."""

    name = "embedding"

    def __init__(self, model: str = "all-MiniLM-L6-v2"):
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore
        except Exception as exc:  # pragma: no cover - optional dep
            raise RuntimeError(
                "EmbeddingBackend requires the optional 'vector' extra:\n"
                "    pip install -e 'poc/registry[vector]'\n"
                f"(import failed: {exc})"
            )
        self._model = SentenceTransformer(model)

    def _embed(self, texts: List[str]):
        return self._model.encode(texts, normalize_embeddings=True)

    def score(self, a: str, b: str, lang_hint: str = "") -> float:
        va, vb = self._embed([a, b])
        return float(sum(x * y for x, y in zip(va, vb)))  # cosine (already normalized)

    def score_many(self, query: str, candidates: List[str], lang_hint: str = "") -> List[float]:
        vecs = self._embed([query] + candidates)
        q = vecs[0]
        return [float(sum(x * y for x, y in zip(q, c))) for c in vecs[1:]]


def get_backend(name: str = "ast", model: Optional[str] = None) -> SimilarityBackend:
    if name == "ast":
        return AstBackend()
    if name == "embedding":
        return EmbeddingBackend(model=model or "all-MiniLM-L6-v2")
    raise ValueError(f"Unknown similarity backend: {name!r} (use 'ast' or 'embedding')")
