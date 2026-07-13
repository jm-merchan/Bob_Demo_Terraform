# Terraform SDD rules

- Read the applicable constitution in `.foundations/memory/` before generating code.
- Treat the plan/implement boundary as a human approval gate.
- Persist research, designs, and validation reports under `specs/` as directed by the active skill.
- Use HCP Terraform sandbox workspaces for deploy validation; never target production by default.
- Keep credentials in environment variables. Never write tokens or secrets into tracked files.
- Run the validation commands specified by the active workflow before claiming success.

