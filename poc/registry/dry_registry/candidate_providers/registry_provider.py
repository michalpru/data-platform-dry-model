"""Registry candidate provider.

Yields ONE candidate per *logical artifact* (not per binding). Where an artifact has several
implementation bindings (e.g. a warehouse SQL UDF and a PySpark function), a single
representative source is chosen — preferring the engineer's language — so a logical identity
is never double-counted. Each candidate carries full governance: authority, lifecycle, owner
and reuse intent, plus the recommended binding for the engineer's runtime.
"""

from __future__ import annotations

import os
from typing import List, Optional

from ..models import Binding, Candidate, Governance, COVERAGE_REGISTRY
from ..manifests import MANIFESTS_DIR
from ..store import RegistryStore
from .base import CandidateProvider, _language_for


class RegistryCandidateProvider(CandidateProvider):
    def __init__(self, store: RegistryStore, repo_root: str, preferred_language: str = ""):
        self.store = store
        self.repo_root = repo_root
        self.preferred_language = preferred_language

    def _abs(self, source_path: str) -> str:
        return os.path.join(self.repo_root, MANIFESTS_DIR, source_path)

    def _pick_binding(self, bindings) -> Optional[dict]:
        """Choose a representative, source-bearing binding for the whole artifact.

        Preference order: engineer's language -> a SQL binding -> first available.
        Within a language, prefer prod over other envs.
        """
        with_source = [b for b in bindings if b["source_path"]
                       and os.path.isfile(self._abs(b["source_path"]))]
        if not with_source:
            return None
        with_source.sort(key=lambda b: (b["env"] != "prod",))

        def by_lang(lang):
            return [b for b in with_source if _language_for(b["source_path"]) == lang]

        if self.preferred_language:
            same = by_lang(self.preferred_language)
            if same:
                return same[0]
        sql = by_lang("sql")
        if sql:
            return sql[0]
        return with_source[0]

    def iter_candidates(self) -> List[Candidate]:
        out: List[Candidate] = []
        for art in self.store.all_artifacts():
            bindings = self.store.bindings(art["fqn"])
            chosen = self._pick_binding(bindings)
            if chosen is None:
                continue  # no comparable source -> cannot compare code against it
            with open(self._abs(chosen["source_path"]), "r", encoding="utf-8") as fh:
                source_text = fh.read()
            gov = Governance(
                authority="REGISTERED_CANONICAL",
                lifecycle=art["lifecycle_state"] or "UNKNOWN",
                owner=art["owner_team"] or "UNKNOWN",
                reuse_intent=art["reuse_scope"] or "UNKNOWN",
            )
            rec = Binding(
                ref=chosen["physical_ref"],
                system=chosen["system"],
                env=chosen["env"],
                runtime=chosen["runtime"] or "unknown",
                dialect=chosen["dialect"],
                object_type=chosen["object_type"],
                attribution_key=chosen["attribution_key"],
                source_path=chosen["source_path"],
            )
            out.append(
                Candidate(
                    logical_id=art["fqn"],
                    source_text=source_text,
                    title=art["title"] or "",
                    language=_language_for(chosen["source_path"]),
                    dialect=chosen["dialect"],
                    governance=gov,
                    recommended_binding=rec,
                    coverage=COVERAGE_REGISTRY,
                    is_registered=True,
                )
            )
        return out
