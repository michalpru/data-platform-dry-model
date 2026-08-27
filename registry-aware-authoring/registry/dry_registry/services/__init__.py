"""Application services — the "Lookup & Compare Service" layer.

Both the CLI and the MCP server are thin clients over these three services. Business logic
lives here exactly once:

  RegistryService        knows what exists     (search_artifacts, get_artifact, find_composable_artifacts, recommend_composition)
  BindingService         resolves a runtime    (resolve_binding)
  ReuseDetectionService  knows what is similar  (compare_code, scope=registry|workspace)

`build_services()` wires them to a SQLite store, ingesting the registered manifests if the
store is empty so callers never have to remember a separate setup step.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from ..manifests import find_repo_root, load_registered
from ..store import RegistryStore
from .binding_service import BindingService
from .reuse_detection_service import ReuseDetectionService
from .registry_service import RegistryService

DEFAULT_DB = os.path.join(os.path.expanduser("~"), ".dry_registry.sqlite")


@dataclass
class Services:
    registry: RegistryService
    binding: BindingService
    reuse_detection: ReuseDetectionService
    store: RegistryStore
    repo_root: str

    @property
    def comparison(self) -> ReuseDetectionService:
        """Backwards-compatible alias for the reuse-detection service."""
        return self.reuse_detection

    def close(self) -> None:
        self.store.close()


def build_services(
    db: str = DEFAULT_DB,
    repo_root: str | None = None,
    ensure_ingested: bool = True,
) -> Services:
    root = repo_root or find_repo_root()
    store = RegistryStore(db)
    if ensure_ingested and not store.all_artifacts():
        store.ingest(load_registered(root))
    return Services(
        registry=RegistryService(store),
        binding=BindingService(store),
        reuse_detection=ReuseDetectionService(store, root),
        store=store,
        repo_root=root,
    )


__all__ = [
    "Services",
    "build_services",
    "RegistryService",
    "BindingService",
    "ReuseDetectionService",
    "DEFAULT_DB",
]
