# Terraform SDD rules

Bob automatically receives the complete, authoritative rules and design formats in this ruleset:

- `30-module-constitution.md`: all module architecture, security, testing, versioning, Git, and quality rules.
- `31-provider-constitution.md`: all Plugin Framework schema, CRUD, state, diagnostics, testing, and release rules.
- `32-consumer-constitution.md`: all private-module composition, workspace, security, deployment, and validation rules.
- `33-policy-constitution.md`: all tfpolicy structure, enforcement, testing, HCP, and quality rules.
- `40-module-design-template.md` through `43-policy-design-template.md`: the complete required design formats and checklists.

Apply those loaded rules directly; do not tell the user or a subagent to open a constitution or
template before work begins. If a workflow and its constitution disagree, the constitution wins.

Cross-cutting requirements:

- The plan/implement boundary is a mandatory human approval gate.
- Research, designs, and validation reports are persisted under `specs/`.
- Deployment validation uses HCP Terraform sandbox workspaces; production is never the default.
- Credentials stay in environment variables and are never written to tracked files.
- Every validation command required by the active workflow must pass before success is claimed.
- Subagents receive the applicable rules and output format in their prompt, not merely a pathname.
