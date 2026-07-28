"""Registry service — "knows what exists".

Narrow, structured read APIs over the registered artifacts. Returns JSON-serializable
models (never sqlite rows). The LLM is never taught the registry contents; it calls these
tools and reads the results.
"""

from __future__ import annotations

from typing import Dict, List, Optional

from ..models import (
    ArtifactSummary,
    Binding,
    COMPONENT_AUTHOR,
    COMPONENT_REUSE,
    CompositionComponent,
    CompositionRecommendation,
    Governance,
)
from ..store import RegistryStore


def _binding_model(row) -> Binding:
    return Binding(
        ref=row["physical_ref"],
        system=row["system"],
        env=row["env"],
        runtime=row["runtime"] or "unknown",
        dialect=row["dialect"],
        object_type=row["object_type"],
        attribution_key=row["attribution_key"],
        source_path=row["source_path"],
    )


class RegistryService:
    def __init__(self, store: RegistryStore):
        self.store = store

    def _summary(self, row) -> ArtifactSummary:
        fqn = row["fqn"]
        bindings = [_binding_model(b) for b in self.store.bindings(fqn)]
        deps = [
            {"fqn": d["to_fqn"], "relationship": d["relationship"]}
            for d in self.store.dependencies_of(fqn)
        ]
        consumers = [
            {"fqn": d["from_fqn"], "relationship": d["relationship"]}
            for d in self.store.dependents_of(fqn)
        ]
        gov = Governance(
            authority="REGISTERED_CANONICAL",
            lifecycle=row["lifecycle_state"] or "UNKNOWN",
            owner=row["owner_team"] or "UNKNOWN",
            reuse_intent=row["reuse_scope"] or "UNKNOWN",
        )
        return ArtifactSummary(
            fqn=fqn,
            title=row["title"] or "",
            description=row["description"] or "",
            interface_types=(row["interface_types"] or "").split(",") if row["interface_types"] else [],
            governance=gov,
            bindings=bindings,
            dependencies=deps,
            known_consumers=consumers,
        )

    def search_artifacts(
        self,
        intent: str,
        interface_type: Optional[str] = None,
        lifecycle: Optional[str] = None,
        runtime: Optional[str] = None,
    ) -> List[ArtifactSummary]:
        rows = self.store.search(intent, interface=interface_type)
        results = [self._summary(r) for r in rows]
        if lifecycle:
            results = [a for a in results if a.governance.lifecycle == lifecycle]
        if runtime:
            results = [a for a in results if any(b.runtime == runtime for b in a.bindings)]
        # Results stay in the store's relevance (bm25) order — the artifact whose identity
        # matches the intent leads. Authority/lifecycle is reported per result, not used to
        # re-order (which would bury a more-relevant 'shared' artifact under a less-relevant
        # 'certified' one).
        return results

    def get_artifact(self, artifact_id: str) -> Optional[ArtifactSummary]:
        row = self.store.get(artifact_id)
        return self._summary(row) if row else None

    def find_composable_artifacts(self, concepts: List[str]) -> Dict[str, Optional[ArtifactSummary]]:
        """For each concept term, resolve the single most authoritative registered artifact.

        Used by the intent-first flow when there is no direct match for the whole request
        (e.g. no ARPAC artifact): search each component the engineer named, separately.
        """
        out: Dict[str, Optional[ArtifactSummary]] = {}
        for concept in concepts:
            matches = self.search_artifacts(concept)
            out[concept] = matches[0] if matches else None
        return out

    def recommend_composition(
        self,
        intent: str,
        components: List[str],
        runtime: Optional[str] = None,
        dialect: Optional[str] = None,
    ) -> CompositionRecommendation:
        """Intent-first "hero" call: one request in, a ready reuse plan out.

        Wraps `find_composable_artifacts` and adds (a) an optional whole-request match, (b) a
        resolved recommended binding per component for the engineer's runtime, and (c) the
        list of parts that are genuinely new work. The demo — and Copilot — get a single,
        actionable answer instead of orchestrating four calls by hand.
        """
        # Lazy import avoids a circular import (binding_service imports _binding_model here).
        from .binding_service import BindingService

        binder = BindingService(self.store)
        rec = CompositionRecommendation(intent=intent, runtime=runtime, dialect=dialect)

        whole = self.search_artifacts(intent)
        rec.direct_match = whole[0] if whole else None

        for concept in components:
            matches = self.search_artifacts(concept)
            art = matches[0] if matches else None
            if art is None:
                rec.components.append(
                    CompositionComponent(
                        concept=concept,
                        status=COMPONENT_AUTHOR,
                        note="No registered artifact — author and register a new one.",
                    )
                )
                rec.missing.append(concept)
                continue
            resolution = binder.resolve_binding(art.fqn, runtime=runtime, dialect=dialect)
            rec.components.append(
                CompositionComponent(
                    concept=concept,
                    status=COMPONENT_REUSE,
                    artifact=art,
                    recommended_binding=resolution.recommended,
                    note=resolution.note,
                )
            )

        reuse_n = sum(1 for c in rec.components if c.status == COMPONENT_REUSE)
        if rec.direct_match is not None:
            rec.summary = (
                f"A registered artifact already matches the whole request: "
                f"{rec.direct_match.fqn} [{rec.direct_match.governance.lifecycle}]. "
                f"Reuse it instead of re-composing."
            )
        elif reuse_n:
            rec.summary = (
                f"Reuse {reuse_n} registered component(s); author only the "
                f"{len(rec.missing)} missing part(s) and the small composition that joins them."
            )
        else:
            rec.summary = (
                "No registered components matched — this is new work; author and register it."
            )
        return rec

