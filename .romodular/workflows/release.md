# Release-readiness workflow

Use this workflow to assess a release candidate. Publishing remains a separate,
explicitly authorized action.

1. Establish the intended repository, version, branch, and release scope.
2. Confirm a clean or fully understood worktree.
3. Verify version metadata, public API changes, changelog, licensing, and docs.
4. Run supported build, unit-test, install, export, and consumer-package checks.
5. Review CI results for every required host and compiler combination.
6. Inspect release package contents and naming for every generated target.
7. Record hardware checks separately from compile-only embedded validation.
8. Produce a release recommendation with blockers and retained evidence.
