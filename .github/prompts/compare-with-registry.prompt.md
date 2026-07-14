---
mode: agent
description: Code-first registry comparison — check whether selected/authored code re-implements a governed artifact, explain the evidence, and recommend reuse or registration.
tools: ['compare_code', 'get_artifact', 'resolve_binding']
---

# Code-first: is this already governed?

The engineer has code (a selection or file) and wants to know whether it duplicates something
that already exists. Compare it against the registry and explain the result from evidence.

Steps:

1. **Compare.** Call `compare_code(code, language, dialect, scope="registry")` with the
   engineer's code. (Use `scope="workspace"` only if explicitly asked — that path has no
   governance signal.)
2. **Read the evidence, not just the score.** For each top match note the relationship label
   (`DIRECT_MATCH`, `NEAR_MATCH`, `PARTIAL_REIMPLEMENTATION`, `VALID_ALTERNATE_BINDING`,
   `POSSIBLE_DOMAIN_VARIANT`, `INSUFFICIENT_EVIDENCE`), the similarity signals, and the shared
   source entities / operations / concepts the service returned.
3. **Explain why.** Tell the engineer *why* their code matches (or does not), citing the
   shared entities and operations — not merely a number. Remember: similarity is a candidate
   signal; authority (lifecycle, owner) comes from the registry.
4. **Act.**
   - Governed match (`DIRECT_MATCH` / `NEAR_MATCH`) → `get_artifact`, then `resolve_binding`
     for the engineer's runtime, and recommend reusing it.
   - `VALID_ALTERNATE_BINDING` → the code is a legitimate binding of a governed identity on a
     different runtime; resolve the binding for that runtime rather than treating it as a dup.
   - `PARTIAL_REIMPLEMENTATION` / `POSSIBLE_DOMAIN_VARIANT` → reuse the shared parts; confirm
     intent before diverging.
   - `INSUFFICIENT_EVIDENCE` → no strong match; safe to author, but recommend registering the
     new artifact.
5. **Be honest about limits.** If embeddings were skipped or a signal was not computed (the
   result lists coverage warnings), say the evidence is partial and lower your confidence.
   For cross-language pairs there is no AST score — rely on the neutral signal.
