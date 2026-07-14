"""Load DRY artifact manifests from the reference repository.

The registry ingests two things per artifact:
  1. Governance metadata from the *registered* manifest
     (dry-reference-repository/platform/registry/registered/*.yaml).
  2. Source-file paths, resolved from the *domain source* manifest referenced by
     `sourceManifest`, so the duplication engine can fingerprint the real code.
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
# poc/) so the registry manifests stay untouched; override via DRY_DEFAULT_DIALECT.
_DEFAULT_WAREHOUSE_DIALECT = os.environ.get("DRY_DEFAULT_DIALECT", "snowflake")


def infer_runtime_dialect(system: str, object_type: str):
    """Derive (runtime, dialect) from the existing system/objectType fields.

    This lets resolve_binding() filter by runtime/dialect without editing the registry
    YAML: dbt models/macros, SQLMesh models and semantic metrics are all just implementation
    bindings on their respective runtimes.
    """
    s = (system or "").lower()
    o = (object_type or "").lower()
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
    """Walk up from `start` until the folder containing dry-reference-repository is found."""
    cur = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.isdir(os.path.join(cur, "dry-reference-repository")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            raise FileNotFoundError(
                "Could not locate 'dry-reference-repository' walking up from "
                f"{start or os.getcwd()}. Pass --repo-root explicitly."
            )
        cur = parent


def registered_dir(repo_root: str) -> str:
    return os.path.join(
        repo_root, "dry-reference-repository", "platform", "registry", "registered"
    )


def _load_yaml(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def _resolve_source_paths(repo_root: str, source_manifest: str) -> Dict[str, str]:
    """Return {physical_ref-ish key: source_path} from a domain source manifest.

    Handles both `spec.implementation.source` (single) and
    `spec.implementations[].source` (multiple) shapes used by ReusableLogic manifests.
    """
    out: Dict[str, str] = {}
    if not source_manifest or not source_manifest.endswith((".yaml", ".yml")):
        # Some artifacts point sourceManifest at non-YAML files (e.g. pyproject.toml,
        # package.yaml). Only YAML manifests carry the spec.implementation.source we need.
        return out
    abs_path = os.path.join(repo_root, "dry-reference-repository", source_manifest)
    if not os.path.isfile(abs_path):
        # Some source manifests (datasets/metrics) live outside the logic tree; ignore.
        return out
    spec = (_load_yaml(abs_path) or {}).get("spec", {})
    impl = spec.get("implementation")
    if isinstance(impl, dict) and impl.get("source"):
        key = impl.get("symbol") or impl.get("package") or "default"
        out[key] = impl["source"]
    for item in spec.get("implementations", []) or []:
        if isinstance(item, dict) and item.get("source"):
            key = item.get("physicalRef") or item.get("binding") or item["source"]
            out[key] = item["source"]
    return out


def load_registered(repo_root: str) -> List[Artifact]:
    """Parse all registered manifests into Artifact records."""
    rdir = registered_dir(repo_root)
    artifacts: List[Artifact] = []
    for name in sorted(os.listdir(rdir)):
        if not name.endswith(".yaml"):
            continue
        doc = _load_yaml(os.path.join(rdir, name))
        if doc.get("kind") != "DryArtifact":
            continue
        meta = doc.get("metadata", {})
        spec = doc.get("spec", {})
        source_manifest = spec.get("sourceManifest", "")
        source_map = _resolve_source_paths(repo_root, source_manifest)

        bindings: List[Binding] = []
        for impl in spec.get("physicalImplementations", []) or []:
            ref = impl.get("ref", "")
            # Best-effort source resolution: match by physical ref suffix or symbol.
            source_path = None
            for key, sp in source_map.items():
                if key == ref or ref.endswith(str(key)) or str(key).endswith(ref.split(".")[-1]):
                    source_path = sp
                    break
            if source_path is None and len(source_map) == 1:
                source_path = next(iter(source_map.values()))
            runtime, dialect = infer_runtime_dialect(
                impl.get("system", ""), impl.get("objectType", "")
            )
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
                reuse_scope=spec.get("reuseScope", ""),
                owner_team=(meta.get("owner", {}) or {}).get("team", ""),
                source_manifest=source_manifest,
                bindings=bindings,
                dependencies=spec.get("dependencies", []) or [],
                known_consumers=spec.get("knownConsumers", []) or [],
                aliases=meta.get("aliases", []) or spec.get("aliases", []) or [],
            )
        )
    return artifacts
