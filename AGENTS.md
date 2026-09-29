# RoModular agent instructions

This file is the provider-neutral entry point for AI coding agents working in
the RoModular ecosystem.

Before changing this repository:

1. Read `.romodular/CONTRACT.md` completely.
2. Select and read the role that matches the request:
   - Architecture and dependency boundaries: `.romodular/roles/architecture-auditor.md`
   - Repository maintenance: `.romodular/roles/repository-maintainer.md`
   - Release readiness: `.romodular/roles/release-auditor.md`
   - Documentation: `.romodular/roles/documentation-curator.md`
3. When the task matches one of them, follow the applicable procedure under
   `.romodular/workflows/`.

Role documents describe responsibilities; they do not require a particular
agent runtime. If isolated subagents are unavailable or unnecessary, perform
the selected role in the current session.
