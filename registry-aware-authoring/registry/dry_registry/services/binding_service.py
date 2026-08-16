"""Binding service — resolves the recommended physical binding for a runtime.

Given a logical artifact and the engineer's runtime (and optional dialect), select ONE
recommended active binding and return the alternatives. Under the PoC assumption of one
binding per logical artifact this is usually unambiguous; the service still handles the
multi-binding case (e.g. a warehouse UDF plus a PySpark function) deterministically.
"""

from __future__ import annotations

from typing import List, Optional

from ..models import Binding, BindingResolution
from ..store import RegistryStore
from .registry_service import _binding_model


class BindingService:
    def __init__(self, store: RegistryStore):
        self.store = store

    def resolve_binding(
        self,
        artifact_id: str,
        runtime: Optional[str] = None,
        dialect: Optional[str] = None,
    ) -> BindingResolution:
        rows = self.store.bindings(artifact_id)
        res = BindingResolution(
            artifact_fqn=artifact_id,
            requested_runtime=runtime,
            requested_dialect=dialect,
        )
        if not self.store.get(artifact_id):
            res.note = f"'{artifact_id}' is not registered."
            return res
        bindings: List[Binding] = [_binding_model(r) for r in rows]
        if not bindings:
            res.note = "No implementation bindings are registered for this artifact."
            return res

        def matches(b: Binding) -> bool:
            if runtime and b.runtime != runtime:
                return False
            if dialect and b.dialect and b.dialect != dialect:
                return False
            return True

        eligible = [b for b in bindings if matches(b)]
        if not eligible:
            res.recommended = None
            res.alternatives = bindings
            res.note = (
                f"No binding matches runtime={runtime!r} dialect={dialect!r}. "
                f"{len(bindings)} binding(s) exist on other runtimes."
            )
            return res

        # Prefer prod environment for the recommended active binding.
        eligible.sort(key=lambda b: (b.env != "prod", b.env))
        res.recommended = eligible[0]
        res.alternatives = [b for b in bindings if b is not res.recommended]
        return res
