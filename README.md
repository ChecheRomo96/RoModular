# RoModular

RoModular is the documentation portal for the RoModular C++ ecosystem. It
explains the purpose, status, dependencies, and documentation entry point of
each repository. It also provides the cross-platform workspace bootstrap used
to clone and configure the complete ecosystem.

Provider-neutral AI-agent contracts, repository adapters, and reusable skills
live in the separate `RoModularAgents` repository and are installed by the
workspace bootstrap.

**Documentation:** [RoModular on GitHub Pages](https://checheromo96.github.io/RoModular/)

## Workspace CLI (initial delivery)

The local CLI inspects a checked-out workspace; it does not build firmware,
change Git state, fetch remotes, or replace repository-owned workflows.

```sh
./scripts/romodular.sh doctor --root ..
./scripts/romodular.sh status --root ..
./scripts/romodular.sh sync --dry-run --root ..
```

```powershell
./scripts/romodular.ps1 doctor -Root ..
./scripts/romodular.ps1 status -Root ..
./scripts/romodular.ps1 sync -DryRun -Root ..
```

`doctor` reports workspace and tool availability; `status` reports local Git
state and cached upstream drift; `sync --dry-run` is deliberately a plan-only
preview. Builds, tests, packaging, documentation, and target/board selection
remain in each repository's checked-in scripts and CMake presets.

The CLI integration fixtures are intentionally isolated from a developer
workspace and run in the bootstrap CI on macOS and Windows:

```sh
./tests/test-romodular-cli.sh
```

```powershell
./tests/test-romodular-cli.ps1
```
