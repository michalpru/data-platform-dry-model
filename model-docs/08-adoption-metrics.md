# Reuse metrics (structural + behavioral)

## Structural (design + build-time)

Portfolio balance:
- count of shared/certified assets per layer and interface
- concentration: % of consumption served by top N certified assets

Duplication hotspots:
- similar schemas with different names
- parallel lineage graphs producing similar outputs
- repeated metric names/definitions across BI workspaces

## Behavioral (run-time)

Adoption vs bypass:
- % of Tier-1 dashboards invoking certified metrics vs custom calculations
- % of queries hitting certified datasets vs raw tables
- semantic telemetry usage per metric (by team/tool)

Consumer coverage:
- % of in-scope consumers with enough attribution metadata to classify governed vs non-governed consumption

Quality of attribution:
- service identity discipline
- workload tagging

Report coverage alongside adoption rates: an adoption rate is only meaningful where attribution coverage is high.

## Actionability

Metrics should drive decisions:
- consolidate vs tolerate divergence
- promote shared → certified
- add guardrails (access patterns)
- invest in discoverability/lifecycle tooling
