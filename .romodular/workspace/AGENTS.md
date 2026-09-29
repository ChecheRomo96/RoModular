# RoModular workspace instructions

This directory is a multi-repository RoModular workspace.

Before working in any repository:

1. Read `RoModular/.romodular/CONTRACT.md` completely.
2. Identify the repository or repositories explicitly placed in scope by the
   user.
3. Read the root `AGENTS.md` of every repository in scope when it exists.
4. Select the applicable shared role from
   `RoModular/.romodular/roles/` and workflow from
   `RoModular/.romodular/workflows/`.
5. If a repository has no local adapter, inspect its own build and
   documentation before making assumptions, and report the missing adapter.

The expected repositories are:

- `RoModular`: ecosystem documentation and shared governance.
- `RoModularBuild`: reusable build infrastructure.
- `Foundation`: low-level portable C++ library.
- `MCC`: Music Composition Core.
- `MIDILAR`: legacy MIDI and music-technology code pending reconstruction.

Repository proximity does not grant cross-repository authority. Preserve
unrelated changes and do not modify a sibling repository unless the user
explicitly includes it in the current request.
