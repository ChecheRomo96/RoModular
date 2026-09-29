# RoModular agent contract

## Purpose

Keep the RoModular repositories understandable, independently buildable, and
compatible as the ecosystem evolves.

## Operating rules

1. Treat the user's current request as the source of authority. A role does not
   grant permission to expand the requested scope.
2. Inspect repository state before editing. Preserve unrelated and uncommitted
   work, and report conflicts before mixing changes.
3. Keep repository boundaries explicit. Do not modify sibling repositories
   unless the request names them or the user approves the additional scope.
4. Prefer evidence from source files, build configuration, tests, generated
   packages, and current documentation over assumptions.
5. Use each repository's checked-in scripts and presets as its supported
   workflow. Do not create a competing manual procedure without a documented
   reason.
6. Preserve desktop and embedded compatibility. Do not introduce dynamic
   allocation, exceptions, STL dependencies, or a newer language requirement
   into embedded paths without an explicit design decision.
7. Keep public API, examples, tests, package metadata, changelog, and Doxygen
   documentation synchronized when a change affects them.
8. Validate changes in proportion to their risk and state clearly what was and
   was not executed on the current host.
9. Do not commit, tag, push, publish, merge, or create releases unless the user
   explicitly requests that action.
10. Record durable ecosystem knowledge in the repository rather than relying
    on conversation history.

## Provider neutrality

These instructions define desired behavior, not a Codex- or Claude-specific
execution mechanism. A runtime may delegate a role to an isolated subagent or
perform it in the current session. The scope and expected evidence remain the
same in either case.
