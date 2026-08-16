"""Language-neutral transformation profile.

To compare SQL against Python (or two SQL dialects) *without* an AST-level tree comparison,
we extract a small, language-neutral "transformation profile" from each snippet:

  source_entities   tables / DataFrames / sources the code reads
  joins             join operations detected
  filters           filter / WHERE-style predicates (coarse tokens)
  aggregations      sum / count / avg / min / max ...
  group_by          grouping keys / grain
  output_columns    projected / selected output names (best effort)
  concepts          business-vocabulary keywords (revenue, refund, currency, customer, ...)

Extraction is deterministic and best-effort. SQL uses sqlglot when available (regex fallback
otherwise); Python/PySpark uses the stdlib `ast`. The profile feeds two things:
  * the feature scorer (Jaccard overlap) — a cross-language similarity signal, and
  * the embedding document — a normalized natural-language description of the transformation.
"""

from __future__ import annotations

import ast
import logging
import re
from dataclasses import dataclass, field
from typing import Dict, List, Set

try:
    import sqlglot
    from sqlglot import exp

    logging.getLogger("sqlglot").setLevel(logging.ERROR)
    _HAS_SQLGLOT = True
except Exception:  # pragma: no cover
    _HAS_SQLGLOT = False

# Business vocabulary this platform cares about. Kept small and explicit on purpose.
_CONCEPT_TERMS = [
    "revenue", "recogniz", "refund", "credit", "invoice", "order", "netting", "net",
    "currency", "fx", "exchange", "reporting", "customer", "active", "arpac", "gross",
    "amount", "tax", "discount", "margin", "cost", "price", "quantity", "subscription",
]
_AGG_TERMS = ["sum", "count", "avg", "average", "min", "max", "mean", "median"]
_TOKEN = re.compile(r"[a-zA-Z_][a-zA-Z0-9_\.]*")


@dataclass
class TransformationProfile:
    language: str = ""
    source_entities: Set[str] = field(default_factory=set)
    joins: List[str] = field(default_factory=list)
    filters: List[str] = field(default_factory=list)
    aggregations: Set[str] = field(default_factory=set)
    group_by: Set[str] = field(default_factory=set)
    output_columns: Set[str] = field(default_factory=set)
    concepts: Set[str] = field(default_factory=set)

    def feature_set(self) -> Set[str]:
        """Flatten to a bag of typed features for Jaccard overlap (language-neutral)."""
        feats: Set[str] = set()
        feats |= {f"src:{_leaf(e)}" for e in self.source_entities}
        feats |= {f"agg:{a}" for a in self.aggregations}
        feats |= {f"grp:{_leaf(g)}" for g in self.group_by}
        feats |= {f"out:{_leaf(c)}" for c in self.output_columns}
        feats |= {f"concept:{c}" for c in self.concepts}
        if self.joins:
            feats.add(f"joins:{min(len(self.joins), 3)}")
        return {f for f in feats if f.split(":", 1)[1]}

    def to_document(self) -> str:
        """Normalized natural-language description used as the embedding input."""
        parts = [
            f"transformation in {self.language}",
            "reads " + ", ".join(sorted(_leaf(e) for e in self.source_entities)),
            (f"joins {len(self.joins)} sources" if self.joins else "no joins"),
            "aggregates " + ", ".join(sorted(self.aggregations)) if self.aggregations else "",
            "grouped by " + ", ".join(sorted(_leaf(g) for g in self.group_by)) if self.group_by else "",
            "outputs " + ", ".join(sorted(_leaf(c) for c in self.output_columns)) if self.output_columns else "",
            "business concepts " + ", ".join(sorted(self.concepts)) if self.concepts else "",
        ]
        return ". ".join(p for p in parts if p).strip()

    def to_dict(self) -> Dict[str, object]:
        return {
            "language": self.language,
            "source_entities": sorted(self.source_entities),
            "joins": len(self.joins),
            "aggregations": sorted(self.aggregations),
            "group_by": sorted(self.group_by),
            "output_columns": sorted(self.output_columns),
            "concepts": sorted(self.concepts),
        }


def _leaf(name: str) -> str:
    return name.split(".")[-1].strip().lower()


def _concepts_in(text: str) -> Set[str]:
    low = text.lower()
    return {t for t in _CONCEPT_TERMS if t in low}


def extract_profile(text: str, language: str, dialect: str | None = None) -> TransformationProfile:
    if language == "python":
        return _extract_python(text)
    return _extract_sql(text, dialect)


# --- SQL ------------------------------------------------------------------

def _extract_sql(text: str, dialect: str | None) -> TransformationProfile:
    prof = TransformationProfile(language="sql")
    prof.concepts |= _concepts_in(text)
    if _HAS_SQLGLOT:
        try:
            for stmt in sqlglot.parse(text, read=dialect or None):
                if stmt is None:
                    continue
                for t in stmt.find_all(exp.Table):
                    prof.source_entities.add(t.name)
                for j in stmt.find_all(exp.Join):
                    prof.joins.append(j.sql())
                for f in stmt.find_all(exp.Func):
                    fn = (f.sql_name() or "").lower()
                    if fn in _AGG_TERMS:
                        prof.aggregations.add("avg" if fn in ("average", "mean") else fn)
                for g in stmt.find_all(exp.Group):
                    for e in g.expressions:
                        prof.group_by.add(e.sql())
                sel = stmt.find(exp.Select)
                if sel is not None:
                    for e in sel.expressions:
                        alias = e.alias_or_name
                        if alias:
                            prof.output_columns.add(alias)
            if prof.source_entities or prof.aggregations:
                return prof
        except Exception:
            pass
    return _extract_sql_regex(text, prof)


def _extract_sql_regex(text: str, prof: TransformationProfile) -> TransformationProfile:
    low = text.lower()
    for m in re.finditer(r"\b(from|join)\s+([a-zA-Z_][\w\.]*)", low):
        prof.source_entities.add(m.group(2))
        if m.group(1) == "join":
            prof.joins.append(m.group(2))
    for a in _AGG_TERMS:
        if re.search(rf"\b{a}\s*\(", low):
            prof.aggregations.add("avg" if a in ("average", "mean") else a)
    for m in re.finditer(r"group\s+by\s+([\w\.,\s]+)", low):
        for g in m.group(1).split(","):
            g = g.strip().split()[0] if g.strip() else ""
            if g:
                prof.group_by.add(g)
    return prof


# --- Python / PySpark -----------------------------------------------------

def _extract_python(text: str) -> TransformationProfile:
    prof = TransformationProfile(language="python")
    prof.concepts |= _concepts_in(text)
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return _extract_python_regex(text, prof)

    join_calls = {"join", "merge"}
    group_calls = {"groupBy", "groupby", "agg"}
    agg_map = {"sum": "sum", "count": "count", "avg": "avg", "mean": "avg",
               "min": "min", "max": "max"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            attr = node.func.attr
            if attr in join_calls:
                prof.joins.append(attr)
            if attr in group_calls:
                for a in node.args:
                    key = _py_const(a)
                    if key:
                        prof.group_by.add(key)
            if attr in agg_map:
                prof.aggregations.add(agg_map[attr])
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            if node.func.id in agg_map:
                prof.aggregations.add(agg_map[node.func.id])
        # DataFrame parameters / table-like names => source entities.
        if isinstance(node, ast.arg) and node.arg not in ("self", "start_date", "end_date"):
            prof.source_entities.add(node.arg)
        # withColumn("name", ...) => output column.
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr in ("withColumn", "alias", "withColumnRenamed") and node.args):
            key = _py_const(node.args[0])
            if key:
                prof.output_columns.add(key)
    return prof


def _extract_python_regex(text: str, prof: TransformationProfile) -> TransformationProfile:
    for a in _AGG_TERMS:
        if re.search(rf"\b{a}\s*\(", text.lower()):
            prof.aggregations.add("avg" if a in ("average", "mean") else a)
    return prof


def _py_const(node: ast.AST) -> str:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return ""
