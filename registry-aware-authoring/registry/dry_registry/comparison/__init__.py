"""Shared comparison core: normalization, feature extraction, scoring, ranking,
classification and the orchestrating engine. Used identically by both scopes.
"""

from .engine import compare

__all__ = ["compare"]
