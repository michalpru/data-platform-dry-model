"""Minimal local DRY Artifact Registry control plane (PoC).

Layered architecture (see registry-aware-authoring/poc-architecture.md):
  Registry (knows what exists)      -> YAML manifests + SQLite control plane
  Comparison service (what's alike) -> shared normalize/feature/score/rank/classify core
  AI (how to help)                  -> Copilot custom agent + prompts over thin MCP tools

The CLI and the MCP server are both thin clients of the application services in
`dry_registry.services`. Runs fully offline; optional embedding tier is on-demand only.
"""

__version__ = "0.2.0"

from .store import RegistryStore  # noqa: F401
from .services import build_services, Services  # noqa: F401
