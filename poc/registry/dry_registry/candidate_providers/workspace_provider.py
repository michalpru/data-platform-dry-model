"""Workspace candidate provider.

Recursively scans the repositories open in the workspace for SQL / Python / PySpark source
(excluding generated, build, venv and dependency folders) and yields each file as a
candidate. Crucially, workspace candidates carry NO governance signal: authority, lifecycle,
reuse intent and ownership are all UNKNOWN, and coverage is CURRENT_WORKSPACE_ONLY.

This is exactly the Pattern-2 limitation the PoC demonstrates: similarity without authority.
The same comparison engine runs; only the candidate source and (missing) governance differ.
"""

from __future__ import annotations

import os
from typing import List

from ..models import Candidate, Governance, COVERAGE_WORKSPACE
from .base import CandidateProvider, CODE_EXTENSIONS, _language_for

# Folders that stand in for "the repositories open in the workspace".
DEFAULT_ROOTS = ["domains", "enterprise", "platform"]
EXCLUDE_DIRS = {
    "__pycache__", ".git", "node_modules", ".venv", "venv", "env",
    "dist", "build", "target", "_site", ".pytest_cache", "site-assets",
}


class WorkspaceCandidateProvider(CandidateProvider):
    def __init__(self, repo_root: str, roots: List[str] | None = None):
        self.repo_root = repo_root
        self.roots = roots or DEFAULT_ROOTS

    def _iter_paths(self):
        base = os.path.join(self.repo_root, "dry-reference-repository")
        for top in self.roots:
            start = os.path.join(base, top)
            if not os.path.isdir(start):
                continue
            for dirpath, dirnames, filenames in os.walk(start):
                dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
                for fn in filenames:
                    if fn.endswith(CODE_EXTENSIONS) and "__init__" not in fn:
                        yield os.path.join(dirpath, fn)

    def iter_candidates(self) -> List[Candidate]:
        out: List[Candidate] = []
        for path in self._iter_paths():
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    text = fh.read()
            except (OSError, UnicodeDecodeError):
                continue
            rel = os.path.relpath(path, self.repo_root)
            out.append(
                Candidate(
                    logical_id=rel,
                    source_text=text,
                    title=os.path.basename(path),
                    language=_language_for(path),
                    governance=Governance(),  # all UNKNOWN
                    recommended_binding=None,
                    coverage=COVERAGE_WORKSPACE,
                    is_registered=False,
                )
            )
        return out
