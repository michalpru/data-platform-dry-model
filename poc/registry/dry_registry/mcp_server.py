"""Thin MCP stdio server for registry-aware authoring in GitHub Copilot.

Purpose (per the architecture): a *proxy* that exposes the Lookup & Compare Service as a
small set of discoverable, invokable tools. It contains NO business logic — every tool
validates its input, calls an application service, and returns the service's structured JSON.
The LLM (Copilot) reads that evidence; it is never taught the registry contents here.

Tools exposed (registry scope only — the workspace scope is CLI-only by design):
  search_artifacts          intent-first discovery
  get_artifact              fetch one artifact by id
  find_composable_artifacts resolve each named component to its canonical artifact
  resolve_binding           recommended physical binding for a runtime
  compare_code              code-first comparison with evidence

Run:  python -m dry_registry.mcp_server
Requires the optional 'mcp' extra:  pip install -e 'poc/registry[mcp]'
"""

from __future__ import annotations

import os
from typing import List, Optional

try:
    from mcp.server.fastmcp import FastMCP
except Exception as exc:  # pragma: no cover - optional dep
    raise SystemExit(
        "The MCP server needs the optional 'mcp' extra:\n"
        "    pip install -e 'poc/registry[mcp]'\n"
        f"(import failed: {exc})"
    )

from .services import DEFAULT_DB, build_services

# Build the services once. DRY_DB / DRY_REPO_ROOT override the defaults if set.
_SERVICES = build_services(
    db=os.environ.get("DRY_DB") or DEFAULT_DB,
    repo_root=os.environ.get("DRY_REPO_ROOT") or None,
)

mcp = FastMCP("dry-registry")


@mcp.tool()
def search_artifacts(
    intent: str,
    interface_type: Optional[str] = None,
    lifecycle: Optional[str] = None,
    runtime: Optional[str] = None,
) -> list:
    """Intent-first search over registered artifacts. Returns ranked artifacts with their
    governance (authority, lifecycle, owner, reuse intent) and bindings."""
    return [a.to_dict() for a in _SERVICES.registry.search_artifacts(
        intent, interface_type=interface_type, lifecycle=lifecycle, runtime=runtime)]


@mcp.tool()
def get_artifact(artifact_id: str) -> dict:
    """Fetch one registered artifact by its fully-qualified id."""
    art = _SERVICES.registry.get_artifact(artifact_id)
    return art.to_dict() if art else {"error": f"'{artifact_id}' is not registered."}


@mcp.tool()
def find_composable_artifacts(concepts: List[str]) -> dict:
    """Resolve each named component (e.g. the parts of a requested metric) to its canonical
    registered artifact. Use when there is no single artifact for the whole request."""
    mapping = _SERVICES.registry.find_composable_artifacts(concepts)
    return {k: (v.to_dict() if v else None) for k, v in mapping.items()}


@mcp.tool()
def resolve_binding(
    artifact_id: str,
    runtime: Optional[str] = None,
    dialect: Optional[str] = None,
) -> dict:
    """Return the single recommended physical binding for the given runtime (and optional
    dialect), plus any alternatives. Resolve bindings before referencing an artifact."""
    return _SERVICES.binding.resolve_binding(
        artifact_id, runtime=runtime, dialect=dialect).to_dict()


@mcp.tool()
def compare_code(
    code: str,
    language: Optional[str] = None,
    dialect: Optional[str] = None,
    scope: str = "registry",
    top: int = 5,
) -> dict:
    """Code-first comparison of a snippet against registered artifacts. Returns similarity
    signals, shared entities/operations, governance, an advisory relationship label and a
    recommended action — evidence for you to explain and act on. Does not decide for you."""
    return _SERVICES.comparison.compare_code(
        code, language=language or "", dialect=dialect, scope=scope, top=top).to_dict()


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
