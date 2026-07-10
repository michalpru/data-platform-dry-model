"""Minimal local DRY Artifact Registry control plane (PoC).

Two-layer architecture from model-docs/05-artifact-registry-spec.md:
  Layer 1 (declaration): YAML manifests in source control (the reference repo).
  Layer 2 (control plane): this package ingests those manifests into a small SQLite
           store and answers search / resolve / impact / duplicates queries.

Runs fully offline. SQL AST normalization uses sqlglot when installed and degrades
gracefully to a regex normalizer otherwise. Semantic (vector) similarity is an optional
pluggable tier.
"""

__version__ = "0.1.0"

from .store import RegistryStore  # noqa: F401
from .fingerprint import fingerprint, normalize  # noqa: F401
from .similarity import get_backend  # noqa: F401
