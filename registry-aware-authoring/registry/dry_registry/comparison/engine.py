"""The shared comparison engine.

This is the single place where the pipeline lives — feature extraction -> structural &
neutral scoring -> optional embeddings -> ranking -> classification. Both the registry scope
and the workspace scope call this exact function with a list of candidates; only the
candidate source and governance enrichment differ upstream (in the providers).

The engine never calls an LLM. It returns structured evidence so Copilot can explain and act.
"""

from __future__ import annotations

from typing import List, Optional

from ..models import (
    COVERAGE_WORKSPACE,
    Candidate,
    ComparisonResult,
    Evidence,
    Match,
    SimilaritySignals,
)
from .classification import classify, recommend_action
from .features import extract_profile
from .normalizers import detect_lang
from .ranking import combined_score
from .scorers import EmbeddingScorer, EmbeddingUnavailable, ast_score, feature_score, shared_features

WORKSPACE_COVERAGE_WARNINGS = [
    "Warehouse objects (UDFs, tables, views) were not searched.",
    "Semantic-layer / metric runtimes were not searched.",
    "Repositories not checked out into this workspace were not searched.",
    "Package versions not installed locally were not searched.",
    "No governance signal: lifecycle, ownership and reuse intent are UNKNOWN.",
]


def compare(
    code: str,
    candidates: List[Candidate],
    scope: str,
    language: str = "",
    dialect: Optional[str] = None,
    use_embeddings: bool = True,
    embedding_model: Optional[str] = None,
    top: int = 5,
) -> ComparisonResult:
    query_lang = detect_lang(code, language)
    query_profile = extract_profile(code, query_lang, dialect)

    coverage = candidates[0].coverage if candidates else (
        COVERAGE_WORKSPACE if scope == "workspace" else "REGISTERED_ARTIFACTS"
    )
    warnings = list(WORKSPACE_COVERAGE_WARNINGS) if scope == "workspace" else []

    # Pre-compute per-candidate signals (AST + feature). Collect embedding docs for a single
    # batched embedding pass afterwards.
    staged = []  # (candidate, cand_lang, sig, evidence, same_lang, same_identity)
    embed_docs: List[str] = []
    embed_idx: List[int] = []
    for cand in candidates:
        cand_lang = detect_lang(cand.source_text, cand.language)
        same_lang = cand_lang == query_lang
        cand_profile = extract_profile(cand.source_text, cand_lang, cand.dialect)

        a = ast_score(code, cand.source_text, query_lang, cand_lang, dialect, cand.dialect)
        f = feature_score(query_profile, cand_profile)
        src, ops, concepts = shared_features(query_profile, cand_profile)

        sig = SimilaritySignals(
            ast=a,
            feature=round(f, 4),
            method="ast" if a is not None else "feature",
            ast_supported=same_lang,
        )
        ev = Evidence(
            shared_source_entities=src,
            shared_operations=ops,
            shared_concepts=concepts,
        )
        if not same_lang:
            ev.notes.append(
                "Cross-language pair: AST/token comparison is unsupported; using the "
                "language-neutral transformation profile."
            )
        # A registered binding whose language equals the query but different runtime is a
        # legitimate alternate binding of the same identity.
        same_identity = bool(
            cand.is_registered and cand.recommended_binding is not None and not same_lang
        )
        staged.append([cand, cand_lang, sig, ev, same_lang, same_identity])
        embed_docs.append(cand_profile.to_document())
        embed_idx.append(len(staged) - 1)

    # Optional embedding pass — one batched, on-demand encode; nothing is stored.
    if use_embeddings and embed_docs:
        try:
            scorer = EmbeddingScorer(embedding_model)
            scores = scorer.score_many(query_profile.to_document(), embed_docs)
            for i, s in zip(embed_idx, scores):
                sig = staged[i][2]
                sig.embedding = round(float(s), 4)
                sig.embedding_model = scorer.model_id
                if sig.ast is None:
                    sig.method = "embedding"
        except EmbeddingUnavailable:
            warnings.append(
                "Embeddings unavailable (optional 'vector' extra not installed); "
                "used the deterministic feature-profile signal instead."
            )

    matches: List[Match] = []
    for cand, cand_lang, sig, ev, same_lang, same_identity in staged:
        sig.combined = combined_score(sig)
        rel = classify(sig, same_lang, same_identity)
        action = recommend_action(rel, cand.is_registered, cand.governance.lifecycle)
        matches.append(
            Match(
                logical_id=cand.logical_id,
                title=cand.title,
                language=cand_lang,
                governance=cand.governance,
                coverage=cand.coverage,
                similarity=sig,
                evidence=ev,
                recommended_binding=cand.recommended_binding,
                relationship=rel,
                recommended_action=action,
            )
        )

    matches.sort(key=lambda m: m.similarity.combined, reverse=True)
    matches = matches[:top]

    method = "embedding" if (use_embeddings and any(
        m.similarity.embedding is not None for m in matches)) else (
        "ast" if any(m.similarity.ast is not None for m in matches) else "feature")

    summary = _summarize(matches, scope)
    return ComparisonResult(
        scope=scope,
        language=query_lang,
        dialect=dialect,
        method=method,
        coverage=coverage,
        coverage_warnings=warnings,
        matches=matches,
        summary=summary,
    )


def _summarize(matches: List[Match], scope: str) -> str:
    if not matches:
        return "No candidates were available to compare against."
    top = matches[0]
    if top.similarity.combined < 0.30:
        return "No strong match found. Safe to author, but register the new artifact."
    return (
        f"Closest match: {top.logical_id} "
        f"[{top.relationship}] — {top.recommended_action}"
    )
