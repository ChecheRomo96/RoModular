# RoModular agent instructions

RoModular is the ecosystem documentation portal and workspace bootstrap. It
describes repository ownership, maturity, dependencies, governance, and entry
points without absorbing product code or shared build engines.

## Rules

- Keep ecosystem documentation grounded in the repository that owns the
  described behavior; verify claims there.
- RoModularBuild owns generic build mechanics. CPSTL, Foundation, DspCore,
  MCC, and MIDILAR own their source, tests, examples, packages, and release
  policy. Mark planned repositories or capabilities explicitly as planned.
- Preserve the Doxygen group hierarchy, rendered navigation, and GitHub Pages
  deployment. Rebuild Doxygen without warnings after documentation changes.
- Keep the workspace manifest and the shell and PowerShell scripts
  cross-platform and behaviorally aligned; validate both when their shared
  contract changes.
- Do not modify sibling repositories or commit, tag, push, publish, merge, or
  create releases unless the user explicitly requests the action.
