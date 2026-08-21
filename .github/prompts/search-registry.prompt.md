---
mode: agent
description: Intent-first registry search — find and reuse governed artifacts for what the engineer wants to build, composing from registered components when there is no single match.
tools: ['search_artifacts', 'get_artifact', 'find_composable_artifacts', 'recommend_composition', 'resolve_binding']
---

# Intent-first: find what to reuse

The engineer wants to build something (a metric, rule, dataset). Find the governed artifacts
to reuse **before** any new code is written. Use only what the tools return — never invent
artifact ids, bindings or owners.

Steps:

1. **Search the whole request first.** `search_artifacts` with the engineer's stated intent
   (e.g. the metric name). If a single clear match exists, `get_artifact` it and recommend
   reuse — stop here.
2. **No single match? Decompose.** Break the request into the components the engineer named.
   Call `recommend_composition(intent, [component, ...])` — it resolves each named component
   to a registered artifact + binding and flags anything that must be authored. You may also
   call `find_composable_artifacts([component, ...])`, or `search_artifacts` each component
   **separately**. Resolution defaults to **enterprise-wide certified** definitions —
   domain-local canonicals and raw base tables are not selected as reuse targets. Do not infer a
   composition the engineer did not describe.
3. **Report gaps honestly.** For any component with no registered artifact, say so and treat
   it as new work to author and register — do not force an unrelated match to fit.
4. **Resolve bindings.** For every artifact you will reference, call
   `resolve_binding(artifact_id, runtime, dialect)` for the engineer's runtime and use the
   returned recommended binding. Never reference a physical object you guessed. If
   `resolve_binding` returns no binding for the target runtime, report it as a cross-engine /
   missing-binding gap — name the artifact and the engine(s) it *is* bound to, and treat
   provisioning a target-engine binding as an integration requirement. Never invent a physical
   object to bridge engines.
5. **Recommend.** Summarise: which registered artifacts to reuse (with lifecycle + owner from
   the registry), their resolved bindings, and only the small piece of genuinely new, derived
   logic that remains. Prefer certified over shared, but surface the most relevant artifact
   even if it is shared. If there are several plausible matches, present them and let the
   engineer choose.

Example (ARPAC): search "ARPAC" first. If absent, search "net recognized revenue" and
"active customers" separately, resolve each binding, and only then help write the ratio.
