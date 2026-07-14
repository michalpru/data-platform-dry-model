"""Optional code-embedding similarity (advisory tier).

Design (per the PoC's constraints):
  * Compute on demand — no vector database, no persistence. There are only a handful of
    registry artifacts, so we embed the query + all candidate documents in ONE batched call
    and compute cosine in memory, then discard the vectors.
  * The embedding *document* is the language-neutral transformation profile text, so the
    same model can relate SQL and Python.
  * Configurable model; the model id is recorded on the result. Defaults to a small
    code-aware model. Degrades gracefully: if sentence-transformers is not installed the
    caller falls back to feature scoring and reports which method was used.

This tier is advisory only — it never establishes authority. The LLM (Copilot) interprets it.
"""

from __future__ import annotations

from typing import List, Optional

# A small, code-aware default. Heavier code models (Nomic Embed Code, NV-EmbedCode,
# Jina code embeddings) can be selected via `model=` when the environment can afford them.
DEFAULT_MODEL = "jinaai/jina-embeddings-v2-base-code"


class EmbeddingUnavailable(RuntimeError):
    pass


class EmbeddingScorer:
    """Lazily loads a local sentence-transformers model and batches all inputs."""

    def __init__(self, model: Optional[str] = None):
        self.model_id = model or DEFAULT_MODEL
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore
        except Exception as exc:  # pragma: no cover - optional dep
            raise EmbeddingUnavailable(
                "Embedding comparison needs the optional 'vector' extra:\n"
                "    pip install -e 'poc/registry[vector]'\n"
                f"(import failed: {exc})"
            )
        try:
            self._model = SentenceTransformer(self.model_id, trust_remote_code=True)
        except Exception as exc:  # pragma: no cover - model download/runtime issues
            raise EmbeddingUnavailable(
                f"Could not load embedding model '{self.model_id}': {exc}"
            )

    def score_many(self, query_doc: str, candidate_docs: List[str]) -> List[float]:
        """Cosine of the query against each candidate — one batched encode, no storage."""
        if not candidate_docs:
            return []
        vecs = self._model.encode(
            [query_doc] + list(candidate_docs), normalize_embeddings=True
        )
        q = vecs[0]
        return [float(sum(x * y for x, y in zip(q, c))) for c in vecs[1:]]
