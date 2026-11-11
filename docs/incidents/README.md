# Incidents

A record of process failures by the agents working on this repo: a rule that existed and was not followed, a check that was
skipped, damage to the machine or to a build that reached Eric. One file per incident, named `YYYY-MM-DD-short-slug.md`.

An incident file is written by the agent that caused or found it, in the same session, and says:

- **What happened** and what Eric saw, with numbers.
- **Impact**: time lost, wrong results, anything shipped.
- **Cause**: the decision that led to it, not the tool that carried it out.
- **Why the existing safeguard did not hold**, when one existed.
- **What changed** so it does not recur, with the file that now carries the rule.
- **How to notice it earlier** next time.

Plain facts, no blame-shifting and no softening. A bug caught by the test suite before a merge is the system working, not
an incident; a bug that shipped, or a gate that was bypassed, is.

| Date | Incident |
|---|---|
| 2026-11-11 | [Machine overloaded by simulator work run in parallel](2026-11-11-machine-overload.md) |
