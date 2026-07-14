"""Pattern 2 harness: AI workspace similarity search (no registry authority).

This is a THIN wrapper over the same Lookup & Compare Service the registry scope uses — it
just calls `compare_code(..., scope="workspace")`. That is the whole point of the refactor:
normalization, feature extraction, scoring, ranking and classification live once in the
shared comparison core; only the candidate source (workspace files) and the (missing)
governance metadata differ.

What this DELIBERATELY cannot do (the Pattern-2 limitation the PoC demonstrates):
  - It ranks by SIMILARITY, not AUTHORITY. Every match reports authority=UNKNOWN,
    lifecycle=UNKNOWN, reuse_intent=UNKNOWN.
  - It only sees the workspace. Warehouse objects, other repos and uninstalled packages are
    invisible — the result spells this out in its coverage warnings.

The workspace scenario uses NO Copilot agent and NO MCP: the CLI / this harness is the
integration surface. Registry-aware authoring (agent + MCP) is the separate registry scope.

Usage (from poc/workspace-similarity):
    python scan.py --query ../demo/arpac-authoring-scratch.sql
    python scan.py --query ../demo/arpac-authoring-scratch.sql --embeddings
"""

from __future__ import annotations

import argparse
import os
import sys

# Make the registry package importable without installation.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "registry"))

from dry_registry.services import build_services  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--query", required=True, help="File the engineer is authoring.")
    ap.add_argument("--language", default=None, choices=["sql", "python"])
    ap.add_argument("--embeddings", action="store_true",
                    help="Use the on-demand embedding tier (optional 'vector' extra).")
    ap.add_argument("--model", default=None, help="Embedding model id (embedding tier).")
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--repo-root", default=None)
    ap.add_argument("--db", default=":memory:")
    args = ap.parse_args(argv)

    svc = build_services(db=args.db, repo_root=args.repo_root)
    with open(args.query, "r", encoding="utf-8") as fh:
        query = fh.read()

    result = svc.comparison.compare_code(
        query,
        language=args.language or "",
        scope="workspace",
        use_embeddings=args.embeddings,
        embedding_model=args.model,
        top=args.top,
    )

    print(f"Workspace similarity search for {os.path.basename(args.query)} "
          f"(method={result.method})\n")
    print("  Ranked by SIMILARITY ONLY — no lifecycle, ownership or canonical status:\n")
    for m in result.matches:
        s = m.similarity
        sig = " ".join(f"{k}={v:.2f}" for k, v in (
            ("ast", s.ast), ("feat", s.feature), ("emb", s.embedding)) if v is not None)
        print(f"    {s.combined:0.2f}  [{m.relationship}]  {m.logical_id}")
        print(f"          {sig} | authority: {m.governance.authority}")
    print("\n  ⚠ The top match may be a certified canonical, a local copy, or a test fixture —")
    print("    this method cannot tell. That authority gap is what the registry closes (Pattern 3).")
    if result.coverage_warnings:
        print("\n  Coverage caveats:")
        for w in result.coverage_warnings:
            print(f"    - {w}")
    svc.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
