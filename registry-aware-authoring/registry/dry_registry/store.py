"""SQLite control-plane store for the DRY Artifact Registry PoC.

Implements the minimal data model from model-docs/05-artifact-registry-spec.md:
  artifact, implementation_binding, dependency_edge.
Behavioral tables (consumer, usage_edge) and derived duplication_candidate are out of
scope for this PoC (per the task), so only the structural/declared model is persisted.
"""

from __future__ import annotations

import sqlite3
from typing import List, Optional

from .manifests import Artifact

SCHEMA = """
CREATE TABLE IF NOT EXISTS artifact (
    fqn             TEXT PRIMARY KEY,
    title           TEXT,
    description     TEXT,
    interface_types TEXT,          -- comma-separated
    lifecycle_state TEXT,
    reuse_scope     TEXT,
    owner_team      TEXT,
    source_manifest TEXT
);
CREATE TABLE IF NOT EXISTS implementation_binding (
    artifact_fqn    TEXT,
    system          TEXT,
    env             TEXT,
    object_type     TEXT,
    physical_ref    TEXT,
    attribution_key TEXT,
    source_path     TEXT,
    runtime         TEXT,
    dialect         TEXT,
    FOREIGN KEY (artifact_fqn) REFERENCES artifact(fqn)
);
CREATE TABLE IF NOT EXISTS dependency_edge (
    from_fqn     TEXT,
    to_fqn       TEXT,
    relationship TEXT,
    source       TEXT DEFAULT 'declared'
);
CREATE VIRTUAL TABLE IF NOT EXISTS artifact_fts USING fts5(
    fqn, title, description, body
);
"""


class RegistryStore:
    # Bump when the schema changes so stale on-disk databases are rebuilt automatically.
    SCHEMA_VERSION = 2

    def __init__(self, db_path: str = ":memory:"):
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        self._migrate()
        self.conn.executescript(SCHEMA)
        self.conn.execute(f"PRAGMA user_version = {self.SCHEMA_VERSION}")
        self.conn.commit()

    def _migrate(self) -> None:
        """Drop and recreate tables when an older-schema database is opened."""
        version = self.conn.execute("PRAGMA user_version").fetchone()[0]
        if version and version < self.SCHEMA_VERSION:
            for tbl in ("artifact", "implementation_binding", "dependency_edge", "artifact_fts"):
                self.conn.execute(f"DROP TABLE IF EXISTS {tbl}")
            self.conn.commit()

    # ---- ingestion -------------------------------------------------------
    def reset(self) -> None:
        for tbl in ("artifact", "implementation_binding", "dependency_edge", "artifact_fts"):
            self.conn.execute(f"DELETE FROM {tbl}")
        self.conn.commit()

    def ingest(self, artifacts: List[Artifact]) -> int:
        self.reset()
        for a in artifacts:
            self.conn.execute(
                "INSERT INTO artifact VALUES (?,?,?,?,?,?,?,?)",
                (
                    a.fqn,
                    a.title,
                    a.description,
                    ",".join(a.interface_types),
                    a.lifecycle_state,
                    a.reuse_scope,
                    a.owner_team,
                    a.source_manifest,
                ),
            )
            self.conn.execute(
                "INSERT INTO artifact_fts (fqn, title, description, body) "
                "VALUES (?,?,?,?)",
                (a.fqn, a.title, a.description, a.search_text()),
            )
            for b in a.bindings:
                self.conn.execute(
                    "INSERT INTO implementation_binding VALUES (?,?,?,?,?,?,?,?,?)",
                    (
                        a.fqn,
                        b.system,
                        b.env,
                        b.object_type,
                        b.physical_ref,
                        b.attribution_key,
                        b.source_path,
                        b.runtime,
                        b.dialect,
                    ),
                )
            for dep in a.dependencies:
                self.conn.execute(
                    "INSERT INTO dependency_edge VALUES (?,?,?,?)",
                    (a.fqn, dep.get("fqn", ""), dep.get("relationship", ""), "declared"),
                )
        self.conn.commit()
        return len(artifacts)

    # ---- queries ---------------------------------------------------------
    def search(self, query: str, interface: Optional[str] = None) -> List[sqlite3.Row]:
        """Keyword search over registered artifacts (FTS with a LIKE fallback)."""
        rows: List[sqlite3.Row] = []
        try:
            fts_q = " OR ".join(f"{t}*" for t in query.split())
            rows = self.conn.execute(
                "SELECT a.* FROM artifact_fts f JOIN artifact a ON a.fqn = f.fqn "
                # Weight identity columns (title, fqn) above description/body so intent
                # search resolves to the artifact whose *name* matches, not one that merely
                # mentions the term. Column order: fqn, title, description, body.
                "WHERE artifact_fts MATCH ? ORDER BY bm25(artifact_fts, 4.0, 8.0, 1.0, 0.5)",
                (fts_q,),
            ).fetchall()
        except sqlite3.OperationalError:
            rows = []
        if not rows:
            like = f"%{query}%"
            rows = self.conn.execute(
                "SELECT * FROM artifact WHERE fqn LIKE ? OR title LIKE ? OR description LIKE ?",
                (like, like, like),
            ).fetchall()
        if interface:
            rows = [r for r in rows if interface in (r["interface_types"] or "")]
        return rows

    def get(self, fqn: str) -> Optional[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM artifact WHERE fqn = ?", (fqn,)
        ).fetchone()

    def all_artifacts(self) -> List[sqlite3.Row]:
        return self.conn.execute("SELECT * FROM artifact ORDER BY fqn").fetchall()

    def bindings(self, fqn: str) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM implementation_binding WHERE artifact_fqn = ?", (fqn,)
        ).fetchall()

    def all_bindings_with_source(self) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT b.*, a.lifecycle_state, a.owner_team, a.interface_types "
            "FROM implementation_binding b JOIN artifact a ON a.fqn = b.artifact_fqn "
            "WHERE b.source_path IS NOT NULL"
        ).fetchall()

    def dependencies_of(self, fqn: str) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM dependency_edge WHERE from_fqn = ?", (fqn,)
        ).fetchall()

    def dependents_of(self, fqn: str) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM dependency_edge WHERE to_fqn = ?", (fqn,)
        ).fetchall()

    def close(self) -> None:
        self.conn.close()
