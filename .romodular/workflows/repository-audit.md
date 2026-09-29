# Repository audit workflow

Use this workflow for a status review, architecture review, or request asking
what should happen next.

1. Read the shared contract and select the applicable role.
2. Inspect branch, worktree status, recent history, and repository structure.
3. Identify the repository's declared purpose, supported platforms, public API,
   build entry points, tests, packaging, and documentation.
4. Compare documentation and automation claims with checked-in implementation.
5. Run safe read-only checks or existing validation commands when appropriate.
6. Classify findings as blockers, risks, maintenance debt, or future work.
7. Recommend the smallest ordered set of next actions, with dependencies and
   unavailable validation called out explicitly.
