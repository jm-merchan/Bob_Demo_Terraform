# Terraform SDD rules

Cross-cutting requirements (apply to all four workflows):

- The plan/implement boundary is a mandatory human approval gate.
- Research, designs, and validation reports are persisted under `specs/`.
- Deployment validation uses HCP Terraform sandbox workspaces; production is never the default.
- Credentials stay in environment variables and are never written to tracked files.
- Every validation command required by the active workflow must pass before success is claimed.
- Subagents receive the applicable rules and output format in their prompt, not merely a pathname.
- When a workflow skill activates, its **Phase 0** loads the matching constitution skill before any
  work begins. The constitution skill contains the authoritative rules AND design template for that
  workflow. If a workflow and its constitution disagree, the constitution wins.

Workflow entry points:

| Command                  | Constitution skill activated |
|--------------------------|------------------------------|
| `/tf-module-plan`        | `tf-module-constitution`     |
| `/tf-module-implement`   | `tf-module-constitution`     |
| `/tf-provider-plan`      | `tf-provider-constitution`   |
| `/tf-provider-implement` | `tf-provider-constitution`   |
| `/tf-consumer-plan`      | `tf-consumer-constitution`   |
| `/tf-consumer-implement` | `tf-consumer-constitution`   |
| `/tf-policy-plan`        | `tf-policy-constitution`     |
| `/tf-policy-implement`   | `tf-policy-constitution`     |
