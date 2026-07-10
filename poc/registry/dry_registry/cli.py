"""Command-line interface for the DRY Artifact Registry PoC.

Commands:
  ingest      Build the SQLite control plane from the registered manifests.
  search      Keyword search over registered artifacts (authoring-time discovery).
  resolve     Registry-backed canonical resolution for a concept (returns authority).
  impact      Declared-dependency impact analysis (dependencies + dependents).
  duplicates  Fingerprint a candidate file and compare it to REGISTERED artifacts,
              returning similarity AND governance authority (Pattern 3 advantage).

Runs fully offline. Example:
    python -m dry_registry.cli ingest
    python -m dry_registry.cli resolve revenue
    python -m dry_registry.cli duplicates ../demo/arpac-authoring-scratch.sql
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Optional

from .manifests import find_repo_root, load_registered
from .similarity import get_backend
from .store import RegistryStore

DEFAULT_DB = os.path.join(os.path.expanduser("~"), ".dry_registry.sqlite")


def _store(args) -> RegistryStore:
    return RegistryStore(args.db)


def _repo_root(args) -> str:
    return args.repo_root or find_repo_root()


def cmd_ingest(args) -> int:
    root = _repo_root(args)
    store = _store(args)
    n = store.ingest(load_registered(root))
    print(f"Ingested {n} registered artifacts from {root} into {args.db}")
    return 0


def cmd_search(args) -> int:
    store = _store(args)
    rows = store.search(args.query, interface=args.interface)
    if not rows:
        print(f"No registered artifact matches '{args.query}'.")
        return 0
    print(f"Registered artifacts matching '{args.query}':\n")
    for r in rows:
        print(f"  {r['fqn']}")
        print(f"      interface: {r['interface_types']} | lifecycle: {r['lifecycle_state']}"
              f" | owner: {r['owner_team']} | scope: {r['reuse_scope']}")
    return 0


def cmd_resolve(args) -> int:
    store = _store(args)
    rows = store.search(args.concept)
    # Prefer certified, then shared; a canonical answer carries authority, not just similarity.
    order = {"certified": 0, "shared": 1}
    rows = sorted(rows, key=lambda r: order.get(r["lifecycle_state"], 9))
    if not rows:
        print(f"No canonical artifact registered for '{args.concept}'. "
              f"Nothing to reuse — safe to author a new governed artifact.")
        return 0
    top = rows[0]
    print(f"Canonical resolution for '{args.concept}':\n")
    print(f"  ► {top['fqn']}  [{top['lifecycle_state'].upper()}]")
    print(f"      {top['title']} — owned by {top['owner_team']}")
    print(f"      interface: {top['interface_types']} | scope: {top['reuse_scope']}")
    binds = store.bindings(top["fqn"])
    if binds:
        print("      Implementation Bindings:")
        for b in binds:
            print(f"        - {b['system']}/{b['env']}: {b['physical_ref']} ({b['object_type']})")
    deps = store.dependencies_of(top["fqn"])
    if deps:
        print("      Reuses (declared dependencies):")
        for d in deps:
            print(f"        - {d['to_fqn']} ({d['relationship']})")
    print("\n      → Reuse this artifact instead of re-implementing it.")
    if len(rows) > 1:
        print("\n      Other registered matches:")
        for r in rows[1:]:
            print(f"        - {r['fqn']} [{r['lifecycle_state']}]")
    return 0


def cmd_impact(args) -> int:
    store = _store(args)
    art = store.get(args.fqn)
    if not art:
        print(f"'{args.fqn}' is not registered.")
        return 1
    print(f"Impact analysis for {args.fqn} [{art['lifecycle_state']}]\n")
    deps = store.dependencies_of(args.fqn)
    print("  Depends on (upstream):")
    for d in deps or []:
        print(f"    - {d['to_fqn']} ({d['relationship']})")
    if not deps:
        print("    (none declared)")
    dependents = store.dependents_of(args.fqn)
    print("  Consumed by (downstream — would break on an incompatible change):")
    for d in dependents or []:
        print(f"    - {d['from_fqn']} ({d['relationship']})")
    if not dependents:
        print("    (no registered downstream dependents)")
    return 0


def cmd_duplicates(args) -> int:
    store = _store(args)
    with open(args.file, "r", encoding="utf-8") as fh:
        candidate = fh.read()
    backend = get_backend(args.method, model=args.model)
    results = []
    for b in store.all_bindings_with_source():
        if args.interface and args.interface not in (b["interface_types"] or ""):
            continue
        root = _repo_root(args)
        src_abs = os.path.join(root, "dry-reference-repository", b["source_path"])
        if not os.path.isfile(src_abs):
            continue
        with open(src_abs, "r", encoding="utf-8") as fh:
            registered_src = fh.read()
        score = backend.score(candidate, registered_src, lang_hint=args.lang or "")
        results.append((score, b))
    results.sort(key=lambda x: x[0], reverse=True)

    print(f"Duplication check for {os.path.basename(args.file)} "
          f"(method={backend.name}):\n")
    if not results:
        print("  No registered artifacts with source were available to compare.")
        return 0
    for score, b in results[: args.top]:
        flag = "HIGH" if score >= args.threshold else "     "
        print(f"  [{flag}] score={score:0.2f}  {b['artifact_fqn']}  "
              f"[{b['lifecycle_state']}] via {b['physical_ref']}")
    top_score, top_b = results[0]
    print()
    if top_score >= args.threshold:
        print(f"  ⚠ Likely reimplementation of a governed artifact:")
        print(f"    {top_b['artifact_fqn']} [{top_b['lifecycle_state']}] "
              f"owned by {top_b['owner_team']}")
        print(f"    → Route to review / reuse the canonical artifact instead of merging this.")
    else:
        print("  No high-confidence structural match among registered artifacts.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dry-registry", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help=f"SQLite path (default: {DEFAULT_DB})")
    p.add_argument("--repo-root", default=None,
                   help="Repo root containing dry-reference-repository (auto-detected).")
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("ingest", help="Build the control plane from registered manifests.")
    sp.set_defaults(func=cmd_ingest)

    sp = sub.add_parser("search", help="Keyword search over registered artifacts.")
    sp.add_argument("query")
    sp.add_argument("--interface", choices=["callable_logic", "queryable_dataset", "semantic_contract"])
    sp.set_defaults(func=cmd_search)

    sp = sub.add_parser("resolve", help="Registry-backed canonical resolution for a concept.")
    sp.add_argument("concept")
    sp.set_defaults(func=cmd_resolve)

    sp = sub.add_parser("impact", help="Declared-dependency impact analysis.")
    sp.add_argument("fqn")
    sp.set_defaults(func=cmd_impact)

    sp = sub.add_parser("duplicates", help="Fingerprint a file vs registered artifacts.")
    sp.add_argument("file")
    sp.add_argument("--method", default="ast", choices=["ast", "embedding"])
    sp.add_argument("--model", default=None, help="Embedding model (embedding method only).")
    sp.add_argument("--interface", choices=["callable_logic", "queryable_dataset", "semantic_contract"])
    sp.add_argument("--lang", default=None, choices=["sql", "python"])
    sp.add_argument("--threshold", type=float, default=0.60)
    sp.add_argument("--top", type=int, default=5)
    sp.set_defaults(func=cmd_duplicates)

    return p


def main(argv: Optional[list] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
