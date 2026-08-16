"""Candidate providers.

A provider answers one question for the comparison engine: *what should I compare the
engineer's code against, and what do I know about each candidate's governance?*

Both providers emit `models.Candidate` objects with the identical shape. The comparison
engine cannot tell them apart — only the source of the code and the governance enrichment
differ. That is the whole point: normalization, feature extraction, scoring, ranking and
classification exist once and are reused across scopes.
"""

from __future__ import annotations

from typing import List

from ..models import Candidate

CODE_EXTENSIONS = (".sql", ".py")


class CandidateProvider:
    def iter_candidates(self) -> List[Candidate]:
        raise NotImplementedError


def _language_for(path: str) -> str:
    return "python" if path.endswith(".py") else "sql"


__all__ = ["CandidateProvider", "CODE_EXTENSIONS", "_language_for"]
