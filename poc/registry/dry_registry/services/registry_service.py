"""Registry service — "knows what exists".

Narrow, structured read APIs over the registered artifacts. Returns JSON-serializable
models (never sqlite rows). The LLM is never taught the registry contents; it calls these
tools and reads the results.
"""

from __future__ import annotations

from typing import Dict, List, Optional

from ..models import ArtifactSummary, Binding, Governance
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
