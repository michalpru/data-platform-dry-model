"""Pattern 2 harness: AI workspace similarity search (no registry).

Simulates what an AI assistant with workspace-level similarity search can do: scan the
repositories open in the workspace, and rank existing code by structural/semantic similarity
to a candidate the engineer is authoring.

What this DELIBERATELY cannot do (the Pattern-2 limitation the PoC demonstrates):
  - It ranks by SIMILARITY, not AUTHORITY. It has no idea which match is certified,
    who owns it, or whether it is safe to reuse.
  - It only sees what is in the workspace. Artifacts in other repos, or realized only as
    warehouse objects (UDFs, tables), are invisible.

Two backends, selected with --method:
  ast        structural fingerprint (default; offline, deterministic)
  embedding  local sentence-transformers model (optional 'vector' extra)

The engine itself lives in poc/registry/dry_registry; this harness reuses its fingerprint
and similarity code so the AST baseline is identical to the registry's.

Usage (from poc/workspace-similarity):
    python scan.py --query ../demo/arpac-authoring-scratch.sql --method ast
    python scan.py --query ../demo/arpac-authoring-scratch.sql --method embedding
"""

from __future__ import annotations

import argparse
import os
import sys

# Make the registry package importable without installation.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "registry"))

from dry_registry.similarity import get_backend  # noqa: E402

# Folders that stand in for the "repositories open in the workspace".
WORKSPACE_GLOBS = ["domains", "enterprise", "platform"]
CODE_EXTENSIONS = (".sql", ".py")
# Skip packaging / test noise.
SKIP_DIRS = {"__pycache__", ".git", "node_modules"}


def find_repo_root(start: str) -> str:
    cur = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(cur, "dry-reference-repository")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            raise FileNotFoundError("Could not locate dry-reference-repository.")
        cur = parent


def collect_candidates(repo_root: str):
    base = os.path.join(repo_root, "dry-reference-repository")
    for top in WORKSPACE_GLOBS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(base, top)):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(CODE_EXTENSIONS) and "__init__" not in fn:
                    yield os.path.join(dirpath, fn)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--query", required=True, help="File the engineer is authoring.")
    ap.add_argument("--method", default="ast", choices=["ast", "embedding"])
    ap.add_argument("--model", default=None, help="Embedding model (embedding method only).")
    ap.add_argument("--lang", default=None, choices=["sql", "python"])
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--repo-root", default=None)
    args = ap.parse_args(argv)

    repo_root = args.repo_root or find_repo_root(_HERE)
    with open(args.query, "r", encoding="utf-8") as fh:
        query = fh.read()

    backend = get_backend(args.method, model=args.model)
    scored = []
    for path in collect_candidates(repo_root):
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        score = backend.score(query, text, lang_hint=args.lang or "")
        rel = os.path.relpath(path, repo_root)
        scored.append((score, rel))
    scored.sort(key=lambda x: x[0], reverse=True)

    print(f"Workspace similarity search for {os.path.basename(args.query)} "
          f"(method={backend.name})\n")
    print("  Ranked by SIMILARITY ONLY — no lifecycle, ownership, or canonical status:\n")
    for score, rel in scored[: args.top]:
        print(f"    {score:0.2f}  {rel}")
    print("\n  ⚠ The top match may be a certified canonical, a local copy, or a test fixture —")
    print("    this method cannot tell. That authority gap is what the registry closes (Pattern 3).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
