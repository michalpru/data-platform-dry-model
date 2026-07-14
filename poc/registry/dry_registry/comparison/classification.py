"""Advisory relationship classification.

Maps similarity signals to one of the fixed relationship labels. This is a *hint* for the
LLM, never a verdict — the model is expected to read the evidence and decide. Thresholds are
deliberately conservative and documented so behaviour is explainable.
"""

from __future__ import annotations

from ..models import (
    DIRECT_MATCH,
    INSUFFICIENT_EVIDENCE,
    NEAR_MATCH,
    PARTIAL_REIMPLEMENTATION,
    POSSIBLE_DOMAIN_VARIANT,
    VALID_ALTERNATE_BINDING,
    SimilaritySignals,
)

# Thresholds on the AST / token-sequence signal (same-language pairs).
_DIRECT = 0.85
_NEAR = 0.62
# Thresholds on the language-neutral feature/embedding signal (cross-language pairs).
_STRONG_FEATURE = 0.55
_WEAK_FEATURE = 0.30


def classify(
    sig: SimilaritySignals,
    same_language: bool,
    same_logical_identity: bool = False,
) -> str:
    # Registered artifact whose recommended binding is on the engineer's language, but the
    # engineer wrote it in a different runtime => a legitimate alternate binding, not a dup.
    if same_logical_identity and not same_language:
        return VALID_ALTERNATE_BINDING

    if same_language and sig.ast is not None:
        if sig.ast >= _DIRECT:
            return DIRECT_MATCH
        if sig.ast >= _NEAR:
            return NEAR_MATCH
        # Same language but low token overlap — fall through to feature reasoning.

    # Cross-language (AST unsupported) or same-language-but-restructured: use the neutral
    # transformation-profile / embedding signal.
    neutral = max(
        v for v in (sig.feature or 0.0, sig.embedding or 0.0, 0.0)
    )
    if not same_language:
        if neutral >= _STRONG_FEATURE:
            return POSSIBLE_DOMAIN_VARIANT
        if neutral >= _WEAK_FEATURE:
            return PARTIAL_REIMPLEMENTATION
        return INSUFFICIENT_EVIDENCE

    if neutral >= _STRONG_FEATURE:
        return PARTIAL_REIMPLEMENTATION
    if neutral >= _WEAK_FEATURE:
        return PARTIAL_REIMPLEMENTATION
    return INSUFFICIENT_EVIDENCE


def recommend_action(relationship: str, is_registered: bool, lifecycle: str = "") -> str:
    if not is_registered:
        return (
            "Workspace-only match with no governance signal. Verify against the registry "
            "before assuming this is canonical."
        )
    tag = f" ({lifecycle})" if lifecycle else ""
    return {
        DIRECT_MATCH: f"Reuse the registered artifact{tag} instead of re-implementing it.",
        NEAR_MATCH: f"Very likely a re-implementation of the registered artifact{tag}; review and reuse it.",
        PARTIAL_REIMPLEMENTATION: f"Overlaps a registered artifact{tag}; reuse the shared parts rather than copying logic.",
        VALID_ALTERNATE_BINDING: f"This is a valid runtime binding of a registered artifact{tag}; resolve the binding for your runtime.",
        POSSIBLE_DOMAIN_VARIANT: f"May be a domain variant of a registered artifact{tag}; confirm intent before diverging.",
        INSUFFICIENT_EVIDENCE: "No strong match; safe to author, but register the new artifact.",
    }[relationship]
