"""Structured, JSON-serializable results returned by the application services.

Every service returns plain dataclasses (never raw sqlite rows), so the CLI, the MCP
server, and the tests all consume exactly the same shapes. The MCP tools serialise these
with `to_dict()` and hand the JSON to Copilot — the model reads *evidence*, it is never
taught the registry contents.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional

# --- fixed vocabularies ---------------------------------------------------

UNKNOWN = "UNKNOWN"

# Relationship classification (fixed set — advisory signal for the LLM, not a verdict).
DIRECT_MATCH = "DIRECT_MATCH"
NEAR_MATCH = "NEAR_MATCH"
PARTIAL_REIMPLEMENTATION = "PARTIAL_REIMPLEMENTATION"
VALID_ALTERNATE_BINDING = "VALID_ALTERNATE_BINDING"
POSSIBLE_DOMAIN_VARIANT = "POSSIBLE_DOMAIN_VARIANT"
INSUFFICIENT_EVIDENCE = "INSUFFICIENT_EVIDENCE"

RELATIONSHIPS = (
    DIRECT_MATCH,
    NEAR_MATCH,
    PARTIAL_REIMPLEMENTATION,
    VALID_ALTERNATE_BINDING,
    POSSIBLE_DOMAIN_VARIANT,
    INSUFFICIENT_EVIDENCE,
)

# Coverage of a comparison — what the scope could and could not see.
COVERAGE_REGISTRY = "REGISTERED_ARTIFACTS"
COVERAGE_WORKSPACE = "CURRENT_WORKSPACE_ONLY"


def _clean(obj: Any) -> Any:
    """asdict() helper that drops None values for compact JSON."""
    if isinstance(obj, dict):
        return {k: _clean(v) for k, v in obj.items() if v is not None}
    if isinstance(obj, list):
        return [_clean(v) for v in obj]
    return obj


@dataclass
class Governance:
    """Authority metadata. Registry candidates carry real values; workspace = UNKNOWN."""

    authority: str = UNKNOWN            # REGISTERED_CANONICAL | UNKNOWN
    lifecycle: str = UNKNOWN            # certified | shared | ... | UNKNOWN
    owner: str = UNKNOWN
    reuse_intent: str = UNKNOWN         # domain_canonical | shared | ... | UNKNOWN

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class Binding:
    """A physical implementation of a logical artifact on a specific runtime."""

    ref: str
    system: str = ""
    env: str = ""
    runtime: str = UNKNOWN             # warehouse | spark | dbt | semantic | ...
    dialect: Optional[str] = None      # snowflake | spark | ... (None when N/A)
    object_type: str = ""
    attribution_key: str = ""
    source_path: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return _clean(asdict(self))


@dataclass
class SimilaritySignals:
    """Independent similarity signals. None means 'not applicable / not computed'."""

    ast: Optional[float] = None          # token-sequence similarity (same language only)
    feature: Optional[float] = None      # language-neutral transformation-profile overlap
    embedding: Optional[float] = None    # optional code-embedding cosine (advisory)
    combined: float = 0.0                # rank score used for ordering
    method: str = "ast"                  # primary method that drove `combined`
    embedding_model: Optional[str] = None
    ast_supported: bool = True           # False for cross-language pairs

    def to_dict(self) -> Dict[str, Any]:
        return _clean(asdict(self))


@dataclass
class Evidence:
    """Concrete, model-readable evidence for the similarity — never a conclusion."""

    shared_source_entities: List[str] = field(default_factory=list)
    shared_operations: List[str] = field(default_factory=list)
    shared_concepts: List[str] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return _clean(asdict(self))


@dataclass
class Match:
    """One ranked comparison candidate (a logical artifact, not a binding)."""

    logical_id: str
    title: str = ""
    language: str = ""
    governance: Governance = field(default_factory=Governance)
    coverage: str = COVERAGE_REGISTRY
    similarity: SimilaritySignals = field(default_factory=SimilaritySignals)
    evidence: Evidence = field(default_factory=Evidence)
    recommended_binding: Optional[Binding] = None
    relationship: str = INSUFFICIENT_EVIDENCE
    recommended_action: str = ""

    def to_dict(self) -> Dict[str, Any]:
        d = {
            "logical_id": self.logical_id,
            "title": self.title,
            "language": self.language,
            "governance": self.governance.to_dict(),
            "coverage": self.coverage,
            "similarity": self.similarity.to_dict(),
            "evidence": self.evidence.to_dict(),
            "relationship": self.relationship,
            "recommended_action": self.recommended_action,
        }
        if self.recommended_binding is not None:
            d["recommended_binding"] = self.recommended_binding.to_dict()
        return d


@dataclass
class ComparisonResult:
    """Full result of compare_code(): query context, coverage caveats, ranked matches."""

    scope: str
    language: str
    dialect: Optional[str] = None
    method: str = "ast"
    coverage: str = COVERAGE_REGISTRY
    coverage_warnings: List[str] = field(default_factory=list)
    matches: List[Match] = field(default_factory=list)
    summary: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return _clean(
            {
                "scope": self.scope,
                "language": self.language,
                "dialect": self.dialect,
                "method": self.method,
                "coverage": self.coverage,
                "coverage_warnings": self.coverage_warnings,
                "matches": [m.to_dict() for m in self.matches],
                "summary": self.summary,
            }
        )


@dataclass
class ArtifactSummary:
    """A registered artifact as returned by search_artifacts / get_artifact."""

    fqn: str
    title: str = ""
    description: str = ""
    interface_types: List[str] = field(default_factory=list)
    governance: Governance = field(default_factory=Governance)
    bindings: List[Binding] = field(default_factory=list)
    dependencies: List[Dict[str, str]] = field(default_factory=list)
    known_consumers: List[Dict[str, str]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return _clean(
            {
                "fqn": self.fqn,
                "title": self.title,
                "description": self.description,
                "interface_types": self.interface_types,
                "governance": self.governance.to_dict(),
                "bindings": [b.to_dict() for b in self.bindings],
                "dependencies": self.dependencies,
                "known_consumers": self.known_consumers,
            }
        )


@dataclass
class Candidate:
    """A comparison candidate produced by a provider (registry or workspace).

    Both providers emit the SAME shape; only the source of the code and the governance
    enrichment differ. The comparison engine treats them identically.
    """

    logical_id: str
    source_text: str
    title: str = ""
    language: str = ""                 # "" => let the engine detect it
    dialect: Optional[str] = None
    governance: Governance = field(default_factory=Governance)
    recommended_binding: Optional[Binding] = None
    coverage: str = COVERAGE_REGISTRY
    is_registered: bool = True


@dataclass
class BindingResolution:
    """resolve_binding(): the single recommended binding plus any alternatives."""

    artifact_fqn: str
    requested_runtime: Optional[str] = None
    requested_dialect: Optional[str] = None
    recommended: Optional[Binding] = None
    alternatives: List[Binding] = field(default_factory=list)
    note: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return _clean(
            {
                "artifact_fqn": self.artifact_fqn,
                "requested_runtime": self.requested_runtime,
                "requested_dialect": self.requested_dialect,
                "recommended": self.recommended.to_dict() if self.recommended else None,
                "alternatives": [b.to_dict() for b in self.alternatives],
                "note": self.note,
            }
        )
