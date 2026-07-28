"""Reuse detection service — "knows what is similar".

Renamed from `ComparisonService` to business language: this service *detects reuse and
re-implementation*. `compare_code` is scope-agnostic: it selects a candidate provider
(registry or workspace), then runs the ONE shared comparison engine. The engine returns
structured evidence (similarity signals, shared entities/operations, governance, coverage
warnings, recommended binding and an advisory relationship) — enough for Copilot to explain
and act safely.

Intent-first authoring should reach for the registry lookup (`search_artifacts`) *before*
this service. Reuse detection is the verification step, not the entry point.
"""

from __future__ import annotations

from typing import Optional

from ..comparison import compare
from ..comparison.normalizers import detect_lang
from ..candidate_providers import RegistryCandidateProvider, WorkspaceCandidateProvider
from ..models import ComparisonResult
from ..store import RegistryStore


class ReuseDetectionService:
    def __init__(self, store: RegistryStore, repo_root: str):
        self.store = store
        self.repo_root = repo_root

    def compare_code(
        self,
        code: str,
        language: str = "",
        dialect: Optional[str] = None,
        scope: str = "registry",
        use_embeddings: bool = True,
        embedding_model: Optional[str] = None,
        top: int = 5,
    ) -> ComparisonResult:
        query_lang = detect_lang(code, language)
        if scope == "workspace":
            provider = WorkspaceCandidateProvider(self.repo_root)
        else:
            provider = RegistryCandidateProvider(
                self.store, self.repo_root, preferred_language=query_lang
            )
        candidates = provider.iter_candidates()
        return compare(
            code=code,
            candidates=candidates,
            scope=scope,
            language=query_lang,
            dialect=dialect,
            use_embeddings=use_embeddings,
            embedding_model=embedding_model,
            top=top,
        )


# Backwards-compatible alias for any external caller still importing the old name.
ComparisonService = ReuseDetectionService
