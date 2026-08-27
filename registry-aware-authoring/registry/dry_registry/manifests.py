"""Load DRY artifact manifests from the PoC registry.

The registry is a *logical metadata index*: it stores only YAML manifests, never code.
Each registered artifact is a single `kind: DryArtifact` manifest under the manifests root
(registry-aware-authoring/scenarios/scenario-2/registry-manifests/**). Its Implementation Bindings may carry a
`source` pointer — a path, relative to the mocked workspace root
(registry-aware-authoring/scenarios/scenario-2/workspace/), to the real code the binding realizes. The comparison
engine reads that code to fingerprint it; the registry itself holds no implementation.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import yaml


@dataclass
class Binding:
    system: str
    env: str
    object_type: str
    physical_ref: str
    attribution_key: str
    source_path: Optional[str] = None  # resolved from the domain source manifest
    runtime: str = "unknown"           # inferred: warehouse | spark | dbt | semantic
    dialect: Optional[str] = None      # inferred: snowflake | spark | None


# Default SQL dialect for warehouse/dbt objects in this reference platform. Kept here (in
# registry-aware-authoring/) so the registry manifests stay untouched; override via DRY_DEFAULT_DIALECT.
_DEFAULT_WAREHOUSE_DIALECT = os.environ.get("DRY_DEFAULT_DIALECT", "snowflake")

# Root (relative to the repo root) that holds the PoC registry: pure YAML `DryArtifact`
# manifests, organized by domain and a shared/ tier for base tables. No code lives here.
# Override with DRY_MANIFESTS_DIR.
MANIFESTS_DIR = os.environ.get(
    "DRY_MANIFESTS_DIR",
    os.path.join("registry-aware-authoring", "scenarios", "scenario-2", "registry-manifests"),
)

# Root (relative to the repo root) of the mocked workspace that holds the ACTUAL code the
# Implementation Bindings point at (per-scenario, code may be duplicated across scenarios).
# Binding `source` paths are resolved relative to this root. Override with DRY_WORKSPACE_DIR.
WORKSPACE_DIR = os.environ.get(
    "DRY_WORKSPACE_DIR",
    os.path.join("registry-aware-authoring", "scenarios", "scenario-2", "workspace"),
)


def infer_runtime_dialect(system: str, object_type: str):
    """Derive (runtime, dialect) from the existing system/objectType fields.

    This lets resolve_binding() filter by runtime/dialect without editing the registry
    YAML: dbt models/macros, SQLMesh models and semantic metrics are all just implementation
    bindings on their respective runtimes.
    """
    s = (system or "").lower()
    o = (object_type or "").lower()
    if "databricks" in s:
        return "databricks", "databricks"
    if "spark" in s:
        return "spark", "spark"
    if "sqlmesh" in s:
        return "sqlmesh", _DEFAULT_WAREHOUSE_DIALECT
    if "dbt" in s or o in ("macro", "model"):
        return "dbt", _DEFAULT_WAREHOUSE_DIALECT
    if "semantic" in s or o in ("metric", "metric_definition", "semantic_model"):
        return "semantic", None
    if s == "warehouse" or o in ("udf", "table", "view", "function"):
        return "warehouse", _DEFAULT_WAREHOUSE_DIALECT
    return s or "unknown", None


@dataclass
class Artifact:
    fqn: str
    title: str
    description: str
    interface_types: List[str]
    lifecycle_state: str
    reuse_scope: str
    owner_team: str
    source_manifest: str
    entry_role: str = "producer"
    bindings: List[Binding] = field(default_factory=list)
    dependencies: List[Dict[str, str]] = field(default_factory=list)
    known_consumers: List[Dict[str, str]] = field(default_factory=list)
    aliases: List[str] = field(default_factory=list)

    def search_text(self) -> str:
        """Combined lexical document for full-text search: identity, description, aliases,
        dependencies, binding refs and consumer/entity names."""
        parts: List[str] = [
            self.fqn,
            self.title,
            self.description,
            self.reuse_scope,
            " ".join(self.interface_types),
            " ".join(self.aliases),
            " ".join(d.get("fqn", "") for d in self.dependencies),
            " ".join(c.get("fqn", "") for c in self.known_consumers),
            " ".join(b.physical_ref for b in self.bindings),
            " ".join(b.object_type for b in self.bindings),
        ]
        return " ".join(p for p in parts if p)


def find_repo_root(start: Optional[str] = None) -> str:
    """Walk up from `start` until the folder containing the PoC manifests dir is found."""
    cur = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.isdir(os.path.join(cur, MANIFESTS_DIR)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            raise FileNotFoundError(
                f"Could not locate '{MANIFESTS_DIR}' walking up from "
                f"{start or os.getcwd()}. Pass --repo-root explicitly."
            )
        cur = parent


def manifests_dir(repo_root: str) -> str:
    return os.path.join(repo_root, MANIFESTS_DIR)


def workspace_dir(repo_root: str) -> str:
    return os.path.join(repo_root, WORKSPACE_DIR)


def _load_yaml(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def _iter_manifest_files(root: str):
    """Yield every *.yaml manifest under the registry-manifests root, recursively."""
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if name.endswith((".yaml", ".yml")):
                yield os.path.join(dirpath, name)


def load_registered(repo_root: str) -> List[Artifact]:
    """Parse every DryArtifact manifest under the registry-manifests root into Artifacts.

    Single-tier model: each manifest is a `kind: DryArtifact` document whose bindings carry an
    optional `source` (a path relative to the mocked workspace root) to the real code.
    """
    root = manifests_dir(repo_root)
    artifacts: List[Artifact] = []
    for path in _iter_manifest_files(root):
        doc = _load_yaml(path)
        if doc.get("kind") != "DryArtifact":
            continue
        meta = doc.get("metadata", {})
        spec = doc.get("spec", {})
        # The manifest's own path (relative to the registry root) is recorded for provenance.
        source_manifest = os.path.relpath(path, root).replace(os.sep, "/")

        # Whitepaper-aligned vocabulary (Implementation Bindings / Declared Dependencies /
        # Reuse Intent / Entry Role) with fallback to the earlier key names so older
        # manifests keep loading unchanged.
        binding_specs = (
            spec.get("implementationBindings")
            or spec.get("physicalImplementations")
            or []
        )
        dependency_specs = (
            spec.get("declaredDependencies") or spec.get("dependencies") or []
        )
        reuse_intent = spec.get("reuseIntent") or spec.get("reuseScope") or ""
        entry_role = spec.get("entryRole") or "producer"

        bindings: List[Binding] = []
        for impl in binding_specs:
            ref = impl.get("ref", "")
            # Source resolution: the binding declares its own `source` (a path relative to the
            # mocked workspace root). The registry stores only this pointer, never the code.
            source_path = impl.get("source") or None
            runtime, dialect = infer_runtime_dialect(
                impl.get("system", ""), impl.get("objectType", "")
            )
            # An explicit runtime/dialect on the binding overrides inference. This lets one
            # logical artifact expose multiple bindings (e.g. a warehouse UDF and a dbt macro)
            # so resolve_binding can pick the right one for the target engine.
            if impl.get("runtime"):
                runtime = impl.get("runtime")
            if impl.get("dialect"):
                dialect = impl.get("dialect")
            bindings.append(
                Binding(
                    system=impl.get("system", ""),
                    env=impl.get("env", ""),
                    object_type=impl.get("objectType", ""),
                    physical_ref=ref,
                    attribution_key=impl.get("attributionKey", ""),
                    source_path=source_path,
                    runtime=runtime,
                    dialect=dialect,
                )
            )

        artifacts.append(
            Artifact(
                fqn=meta.get("fqn", ""),
                title=meta.get("title", ""),
                description=(meta.get("description", "") or "").strip(),
                interface_types=spec.get("interfaceTypes", []) or [],
                lifecycle_state=(meta.get("lifecycle", {}) or {}).get("state", ""),
                reuse_scope=reuse_intent,
                owner_team=(meta.get("owner", {}) or {}).get("team", ""),
                source_manifest=source_manifest,
                entry_role=entry_role,
                bindings=bindings,
                dependencies=dependency_specs,
                known_consumers=spec.get("knownConsumers", []) or [],
                aliases=meta.get("aliases", []) or spec.get("aliases", []) or [],
            )
        )
    return artifacts
