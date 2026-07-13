# IBM Bob usage

This repository includes a Bob-native adapter for the Terraform SDD harness. The original Claude
Code and GitHub Copilot integrations remain available; Bob uses the project files under `.bob/`.

## What is mapped

- `AGENTS.md` supplies persistent repository context.
- `.bob/skills/` contains the 32 upstream Agent Skills, including all eight orchestrators.
- `.bob/commands/` exposes the same eight `/tf-...` entry points.
- `.bob/agents/` contains the 20 specialist role definitions used to prompt Bob subagents.
- `.bob/mcp.json` configures Terraform and AWS documentation MCP servers.
- `.bob/custom_modes.yaml` adds a `Terraform SDD` mode with the required tool groups.
- `.bob/rules/` translates legacy harness tool wording and enforces cross-cutting guardrails.
- `.bobignore` prevents Bob from reading common secrets, Terraform state, and generated data.

## Start

1. Install IBM Bob IDE or Bob Shell, clone this repository, and open its root directory.
2. Export the credentials required by the selected workflow, especially `TFE_TOKEN` and
   `GITHUB_TOKEN`. Never store them in the repository.
3. Enable project MCP servers in Bob settings and review each server before allowing tools.
4. Use **Terraform SDD** mode. If project skills are not listed there in your Bob version, use
   **Advanced** mode; Bob skills are supported there by default.
5. Type `/` and choose one of the eight Terraform commands, for example:

   ```text
   /tf-module-plan secure-s3 aws Create an encrypted private S3 module
   ```

6. Review and approve the generated design before running the matching implement command.

## Compatibility notes

The upstream skills use a few generic/legacy tool names. `.bob/rules/20-harness-adapter.md` maps
those names to Bob tools and tells the orchestrator how to load specialist prompts. Bob's custom
commands document positional arguments; the command wrappers concatenate the first nine arguments
and expose them to the skill as the logical `$ARGUMENTS` input.

MCP servers run local processes with the same operating-system permissions as Bob. Keep approvals
enabled, pin server versions for regulated use, and validate the server source before deployment.

