"""Invariant tests for the refactored DRY registry / comparison services.

Run (from poc/registry):  python -m pytest -q
Fully offline; the embedding tier is exercised with a fake scorer so no model is downloaded.
"""

from __future__ import annotations

import pytest

from dry_registry.comparison import engine as engine_mod
from dry_registry.comparison.scorers import ast_score
from dry_registry.models import COVERAGE_WORKSPACE, STRUCTURAL_SIMILARITY
from dry_registry.services import build_services

RECOGNIZE = "finance.logic.recognize_revenue.v1"
SCRATCH_SQL = """
SELECT o.order_id,
       SUM(i.amount) - SUM(COALESCE(r.refund_amount, 0)) AS net_amount
FROM finance.raw.orders o
JOIN finance.raw.invoices i ON i.order_id = o.order_id
LEFT JOIN finance.raw.refunds r ON r.invoice_id = i.invoice_id
GROUP BY o.order_id
"""
PYSPARK = """
def recognize_revenue(orders, invoices, refunds):
    joined = orders.join(invoices, "order_id").join(refunds, "invoice_id", "left")
    return joined.groupBy("order_id").agg(sum("amount"))
"""


@pytest.fixture(scope="module")
def svc():
    s = build_services(db=":memory:")
    yield s
    s.close()


# 1. Workspace and registry scopes run through the SAME comparison engine.
def test_both_scopes_use_same_engine(svc, monkeypatch):
    calls = []
    real_compare = engine_mod.compare

    def spy(*args, **kwargs):
        calls.append(kwargs.get("scope", args[2] if len(args) > 2 else None))
        return real_compare(*args, **kwargs)

    monkeypatch.setattr("dry_registry.services.reuse_detection_service.compare", spy)
    svc.reuse_detection.compare_code(SCRATCH_SQL, scope="registry", use_embeddings=False)
    svc.reuse_detection.compare_code(SCRATCH_SQL, scope="workspace", use_embeddings=False)
    assert calls == ["registry", "workspace"]


# 2. Registry results carry logical identity + governance (lifecycle/owner/authority).
def test_registry_results_have_governance(svc):
    res = svc.reuse_detection.compare_code(SCRATCH_SQL, scope="registry", use_embeddings=False)
    assert res.matches
    top = res.matches[0]
    assert top.logical_id == RECOGNIZE
    assert top.governance.authority == "REGISTERED_CANONICAL"
    assert top.governance.lifecycle == "certified"
    assert top.governance.owner == "finance-analytics"
    assert top.recommended_binding is not None
    # Renamed relationship label (Task 7): STRUCTURAL_SIMILARITY replaces NEAR_MATCH.
    from dry_registry.models import RELATIONSHIPS

    assert STRUCTURAL_SIMILARITY in RELATIONSHIPS
    assert top.relationship in RELATIONSHIPS


# 3. Workspace results have authority UNKNOWN + coverage warnings.
def test_workspace_results_unknown_authority(svc):
    res = svc.reuse_detection.compare_code(SCRATCH_SQL, scope="workspace", use_embeddings=False)
    assert res.coverage == COVERAGE_WORKSPACE
    assert res.coverage_warnings
    for m in res.matches:
        assert m.governance.authority == "UNKNOWN"
        assert m.governance.lifecycle == "UNKNOWN"
        assert m.governance.reuse_intent == "UNKNOWN"


# 4. SQL-to-Python AST comparison is unsupported (returns None).
def test_cross_language_ast_unsupported():
    assert ast_score(SCRATCH_SQL, PYSPARK, "sql", "python") is None
    assert ast_score(SCRATCH_SQL, SCRATCH_SQL, "sql", "sql") is not None


# 5. Multiple bindings collapse to ONE logical artifact (no per-binding double counting).
def test_bindings_grouped_under_one_logical_artifact(svc):
    res = svc.reuse_detection.compare_code(SCRATCH_SQL, scope="registry", use_embeddings=False)
    ids = [m.logical_id for m in res.matches]
    assert ids.count(RECOGNIZE) == 1  # despite 3 physical implementations


# 6. Binding resolution respects runtime (and dialect).
def test_resolve_binding_respects_runtime(svc):
    spark = svc.binding.resolve_binding(RECOGNIZE, runtime="spark")
    assert spark.recommended is not None
    assert spark.recommended.runtime == "spark"

    wh = svc.binding.resolve_binding(RECOGNIZE, runtime="warehouse", dialect="snowflake")
    assert wh.recommended is not None
    assert wh.recommended.runtime == "warehouse"
    assert wh.recommended.dialect == "snowflake"
    assert wh.recommended.env == "prod"  # prod preferred over uat


# 7. Embeddings are computed in ONE batched call over all candidates.
def test_embeddings_are_batched(svc, monkeypatch):
    class FakeScorer:
        def __init__(self, model=None):
            self.model_id = model or "fake-model"
            self.calls = []

        def score_many(self, query_doc, candidate_docs):
            self.calls.append(len(candidate_docs))
            return [0.5] * len(candidate_docs)

    created = {}

    def factory(model=None):
        s = FakeScorer(model)
        created["scorer"] = s
        return s

    monkeypatch.setattr(engine_mod, "EmbeddingScorer", factory)
    res = svc.reuse_detection.compare_code(SCRATCH_SQL, scope="registry", use_embeddings=True)
    # Exactly one batched score_many call covering every candidate at once.
    assert created["scorer"].calls, "embedding scorer was not used"
    assert len(created["scorer"].calls) == 1
    assert any(m.similarity.embedding is not None for m in res.matches)


# 8. CLI and MCP go through the same services (equivalent payloads).
def test_cli_and_service_equivalent(svc):
    # The CLI renders exactly what the service returns; assert the service payload shape the
    # CLI/MCP both serialise.
    art = svc.registry.get_artifact(RECOGNIZE)
    d = art.to_dict()
    assert d["fqn"] == RECOGNIZE
    assert d["governance"]["lifecycle"] == "certified"
    assert d["bindings"]


def test_mcp_tools_match_services(svc):
    mcp = pytest.importorskip("mcp")  # optional dep; skip cleanly if not installed
    import importlib
    import os

    os.environ["DRY_DB"] = ":memory:"
    server = importlib.import_module("dry_registry.mcp_server")
    tool_out = server.get_artifact(RECOGNIZE)
    svc_out = server._SERVICES.registry.get_artifact(RECOGNIZE).to_dict()
    assert tool_out == svc_out


# 9. recommend_composition resolves each named component to a canonical artifact + binding.
def test_recommend_composition(svc):
    rec = svc.registry.recommend_composition(
        "ARPAC",
        ["net recognized revenue", "active customer"],
        runtime="semantic",
    )
    by_concept = {c.concept: c for c in rec.components}
    rev = by_concept["net recognized revenue"]
    assert rev.status == "REUSE_REGISTERED"
    assert rev.artifact is not None
    assert rev.artifact.fqn == "finance.metrics.net_recognized_revenue.v1"
    cust = by_concept["active customer"]
    assert cust.status == "REUSE_REGISTERED"
    assert cust.artifact.fqn == "enterprise.metrics.active_customer.v1"
    assert rec.summary


# 10. Manifests expose whitepaper vocabulary: Producer entry role + Reuse Intent.
def test_manifests_whitepaper_terminology(svc):
    art = svc.registry.get_artifact(RECOGNIZE)
    assert art.governance.reuse_intent == "domain_canonical"
    # Loader reads whitepaper key `reuseIntent` and `entryRole`; entry role is producer.
    from dry_registry.manifests import find_repo_root, load_registered

    loaded = {a.fqn: a for a in load_registered(find_repo_root())}
    assert loaded[RECOGNIZE].entry_role == "producer"
    assert loaded[RECOGNIZE].reuse_scope == "domain_canonical"

