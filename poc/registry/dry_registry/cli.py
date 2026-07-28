"""Command-line client for the DRY Artifact Registry PoC.

The CLI is a THIN client: it parses arguments, calls the application services in
`dry_registry.services`, and renders the structured result. It never contains business
logic and it never goes through the MCP server — the engineer runs it directly against the
Lookup & Compare Service. Use `--json` on any command to get the raw service payload.

Commands:
  ingest          Build / refresh the SQLite control plane from the registered manifests.
  search          Intent-first search over registered artifacts (start here).
  recommend       One-call reuse plan for a request (search + compose + bind).
  get             Fetch one registered artifact by id.
  resolve         Canonical resolution for a concept (returns authority).
  resolve-binding Recommended physical binding for a runtime (+ alternatives).
  composables     Resolve each named component to its canonical registered artifact.
  compare         Code-first verification (scope=registry|workspace) with evidence.
  impact          Declared-dependency impact analysis.

Runs fully offline. Examples:
    python -m dry_registry.cli ingest
    python -m dry_registry.cli search "recognize revenue"
    python -m dry_registry.cli compare ../demo/arpac-authoring-scratch.sql
    python -m dry_registry.cli compare selected.sql --scope workspace
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Optional

from .manifests import find_repo_root, load_registered
from .services import DEFAULT_DB, build_services


def _services(args):
    return build_services(db=args.db, repo_root=args.repo_root)


def _emit(args, payload) -> None:
    if getattr(args, "json", False):
        print(json.dumps(payload, indent=2))


# --- commands -------------------------------------------------------------

def cmd_ingest(args) -> int:
    root = args.repo_root or find_repo_root()
    svc = build_services(db=args.db, repo_root=root, ensure_ingested=False)
    n = svc.store.ingest(load_registered(root))
    svc.close()
    print(f"Ingested {n} registered artifacts from {root} into {args.db}")
    return 0


def cmd_search(args) -> int:
    svc = _services(args)
    results = svc.registry.search_artifacts(
        args.query, interface_type=args.interface, lifecycle=args.lifecycle, runtime=args.runtime
    )
    _emit(args, [a.to_dict() for a in results])
    if not args.json:
        if not results:
            print(f"No registered artifact matches '{args.query}'.")
        else:
            print(f"Registered artifacts matching '{args.query}':\n")
            for a in results:
                g = a.governance
                print(f"  {a.fqn}")
                print(f"      {a.title}")
                print(f"      lifecycle: {g.lifecycle} | owner: {g.owner} | "
                      f"reuse: {g.reuse_intent} | interfaces: {','.join(a.interface_types)}")
    svc.close()
    return 0


def cmd_get(args) -> int:
    svc = _services(args)
    art = svc.registry.get_artifact(args.artifact_id)
    if art is None:
        print(f"'{args.artifact_id}' is not registered.")
        svc.close()
        return 1
    _emit(args, art.to_dict())
    if not args.json:
        g = art.governance
        print(f"{art.fqn}  [{g.lifecycle}]")
        print(f"  {art.title}")
        print(f"  owner: {g.owner} | reuse: {g.reuse_intent} | authority: {g.authority}")
        if art.bindings:
            print("  bindings:")
            for b in art.bindings:
                d = f"/{b.dialect}" if b.dialect else ""
                print(f"    - {b.runtime}{d} {b.env}: {b.ref} ({b.object_type})")
        if art.dependencies:
            print("  depends on:")
            for dep in art.dependencies:
                print(f"    - {dep['fqn']} ({dep['relationship']})")
    svc.close()
    return 0


def cmd_resolve(args) -> int:
    svc = _services(args)
    results = svc.registry.search_artifacts(args.concept)
    _emit(args, results[0].to_dict() if results else {})
    if not args.json:
        if not results:
            print(f"No canonical artifact registered for '{args.concept}'. "
                  f"Nothing to reuse — safe to author a new governed artifact.")
        else:
            top = results[0]
            g = top.governance
            print(f"Canonical resolution for '{args.concept}':\n")
            print(f"  \u25ba {top.fqn}  [{g.lifecycle.upper()}]")
            print(f"      {top.title} — owned by {g.owner}")
            print(f"      reuse intent: {g.reuse_intent}")
            if len(results) > 1:
                print("\n      Other registered matches:")
                for a in results[1:]:
                    print(f"        - {a.fqn} [{a.governance.lifecycle}]")
            print("\n      → Reuse this artifact instead of re-implementing it.")
    svc.close()
    return 0


def cmd_resolve_binding(args) -> int:
    svc = _services(args)
    res = svc.binding.resolve_binding(args.artifact_id, runtime=args.runtime, dialect=args.dialect)
    _emit(args, res.to_dict())
    if not args.json:
        print(f"Binding resolution for {res.artifact_fqn} "
              f"(runtime={args.runtime}, dialect={args.dialect}):\n")
        if res.recommended:
            b = res.recommended
            d = f"/{b.dialect}" if b.dialect else ""
            print(f"  \u25ba recommended: {b.runtime}{d} {b.env}: {b.ref} ({b.object_type})")
        else:
            print("  \u25ba no matching binding")
        if res.note:
            print(f"  note: {res.note}")
        if res.alternatives:
            print("  alternatives:")
            for b in res.alternatives:
                d = f"/{b.dialect}" if b.dialect else ""
                print(f"    - {b.runtime}{d} {b.env}: {b.ref}")
    svc.close()
    return 0


def cmd_compare(args) -> int:
    svc = _services(args)
    with open(args.file, "r", encoding="utf-8") as fh:
        code = fh.read()
    result = svc.reuse_detection.compare_code(
        code,
        language=args.language or "",
        dialect=args.dialect,
        scope=args.scope,
        use_embeddings=not args.no_embeddings,
        embedding_model=args.model,
        top=args.top,
    )
    _emit(args, result.to_dict())
    if not args.json:
        print(f"Comparison for {os.path.basename(args.file)} "
              f"(scope={result.scope}, method={result.method}):\n")
        for m in result.matches:
            s = m.similarity
            sig = " ".join(
                f"{k}={v:.2f}" for k, v in (
                    ("ast", s.ast), ("feat", s.feature), ("emb", s.embedding)
                ) if v is not None
            )
            print(f"  [{m.relationship}] {m.logical_id}")
            print(f"      {sig} (combined={s.combined:.2f}) | "
                  f"authority: {m.governance.authority} | lifecycle: {m.governance.lifecycle}")
            if m.evidence.shared_concepts or m.evidence.shared_source_entities:
                ev = ", ".join(m.evidence.shared_source_entities + m.evidence.shared_concepts)
                print(f"      shared: {ev}")
            print(f"      → {m.recommended_action}")
        print(f"\n  {result.summary}")
        if result.coverage_warnings:
            print("\n  Coverage caveats:")
            for w in result.coverage_warnings:
                print(f"    - {w}")
    svc.close()
    return 0


def cmd_composables(args) -> int:
    svc = _services(args)
    mapping = svc.registry.find_composable_artifacts(args.concepts)
    _emit(args, {k: (v.to_dict() if v else None) for k, v in mapping.items()})
    if not args.json:
        print("Composable component resolution:\n")
        for concept, art in mapping.items():
            if art:
                print(f"  {concept:<24} → {art.fqn} [{art.governance.lifecycle}]")
            else:
                print(f"  {concept:<24} → (no registered artifact — author + register)")
    svc.close()
    return 0


def cmd_recommend(args) -> int:
    svc = _services(args)
    rec = svc.registry.recommend_composition(
        args.intent, args.components, runtime=args.runtime, dialect=args.dialect
    )
    _emit(args, rec.to_dict())
    if not args.json:
        print(f"Composition recommendation for '{args.intent}':\n")
        if rec.direct_match:
            dm = rec.direct_match
            print(f"  \u25ba Whole request already registered: {dm.fqn} "
                  f"[{dm.governance.lifecycle}] — reuse it.\n")
        for c in rec.components:
            if c.status == "REUSE_REGISTERED" and c.artifact:
                g = c.artifact.governance
                print(f"  reuse  {c.concept:<22} → {c.artifact.fqn} [{g.lifecycle}]")
                if c.recommended_binding:
                    b = c.recommended_binding
                    d = f"/{b.dialect}" if b.dialect else ""
                    print(f"         binding: {b.runtime}{d} {b.env}: {b.ref}")
            else:
                print(f"  author {c.concept:<22} → (no registered artifact — author + register)")
        print(f"\n  {rec.summary}")
    svc.close()
    return 0


def cmd_impact(args) -> int:
    svc = _services(args)
    art = svc.registry.get_artifact(args.fqn)
    if art is None:
        print(f"'{args.fqn}' is not registered.")
        svc.close()
        return 1
    payload = {
        "fqn": art.fqn,
        "lifecycle": art.governance.lifecycle,
        "depends_on": art.dependencies,
        "consumed_by": art.known_consumers,
    }
    _emit(args, payload)
    if not args.json:
        print(f"Impact analysis for {art.fqn} [{art.governance.lifecycle}]\n")
        print("  Depends on (upstream):")
        for d in art.dependencies or [{"fqn": "(none declared)", "relationship": ""}]:
            print(f"    - {d['fqn']} ({d.get('relationship','')})".rstrip(" ()"))
        print("  Consumed by (downstream — would break on an incompatible change):")
        for d in art.known_consumers or [{"fqn": "(no registered downstream dependents)", "relationship": ""}]:
            print(f"    - {d['fqn']} ({d.get('relationship','')})".rstrip(" ()"))
    svc.close()
    return 0


# --- parser ---------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dry-registry", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help=f"SQLite path (default: {DEFAULT_DB})")
    p.add_argument("--repo-root", default=None,
                   help="Repo root containing dry-reference-repository (auto-detected).")
    p.add_argument("--json", action="store_true", help="Emit the raw structured JSON payload.")
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("ingest", help="Build the control plane from registered manifests.")
    sp.set_defaults(func=cmd_ingest)

    sp = sub.add_parser("search", help="Intent-first search over registered artifacts.")
    sp.add_argument("query")
    sp.add_argument("--interface", choices=["callable_logic", "queryable_dataset", "semantic_contract"])
    sp.add_argument("--lifecycle", default=None)
    sp.add_argument("--runtime", default=None)
    sp.set_defaults(func=cmd_search)

    sp = sub.add_parser("get", help="Fetch one registered artifact by id.")
    sp.add_argument("artifact_id")
    sp.set_defaults(func=cmd_get)

    sp = sub.add_parser("resolve", help="Canonical resolution for a concept.")
    sp.add_argument("concept")
    sp.set_defaults(func=cmd_resolve)

    sp = sub.add_parser("resolve-binding", help="Recommended physical binding for a runtime.")
    sp.add_argument("artifact_id")
    sp.add_argument("--runtime", default=None, help="warehouse | spark | dbt | semantic")
    sp.add_argument("--dialect", default=None, help="snowflake | spark | ...")
    sp.set_defaults(func=cmd_resolve_binding)

    sp = sub.add_parser("compare", aliases=["compare-code", "duplicates"],
                        help="Code-first comparison with evidence (scope=registry|workspace).")
    sp.add_argument("file")
    sp.add_argument("--scope", default="registry", choices=["registry", "workspace"])
    sp.add_argument("--language", default=None, choices=["sql", "python"])
    sp.add_argument("--dialect", default=None)
    sp.add_argument("--no-embeddings", action="store_true",
                    help="Skip the optional embedding tier (structural + feature only).")
    sp.add_argument("--model", default=None, help="Embedding model id (embedding tier).")
    sp.add_argument("--top", type=int, default=5)
    sp.set_defaults(func=cmd_compare)

    sp = sub.add_parser("composables", help="Resolve each named component to its canonical artifact.")
    sp.add_argument("concepts", nargs="+")
    sp.set_defaults(func=cmd_composables)

    sp = sub.add_parser("recommend", help="One-call reuse plan for a request (search + compose + bind).")
    sp.add_argument("intent", help="The whole business request, e.g. 'ARPAC'.")
    sp.add_argument("--component", dest="components", action="append", default=[],
                    metavar="CONCEPT", help="A named component to resolve (repeatable).")
    sp.add_argument("--runtime", default=None, help="warehouse | spark | dbt | semantic")
    sp.add_argument("--dialect", default=None, help="snowflake | spark | ...")
    sp.set_defaults(func=cmd_recommend)

    sp = sub.add_parser("impact", help="Declared-dependency impact analysis.")
    sp.add_argument("fqn")
    sp.set_defaults(func=cmd_impact)

    return p


def main(argv: Optional[list] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
