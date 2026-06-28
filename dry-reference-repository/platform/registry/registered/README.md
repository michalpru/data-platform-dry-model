# Registered artifacts

This folder holds registry manifest snapshots for **certified or shared artifacts** — those explicitly promoted to be reused beyond their originating team.

**Ownership is retained by the declaring team** — Finance Analytics owns `finance.reporting.*`, Data Governance owns `enterprise.*`.  
The registry records the artifact; it does not transfer ownership.

**How entries get here:**  
CI/CD parses domain manifests on merge to main and publishes entries here. Manual edits are only permitted at certification gates.

**What does NOT belong here:**  
Domain-local artifacts (`lifecycle: local`) — those stay in their domain repo.

Start with `INDEX.md` to see what is currently registered.
