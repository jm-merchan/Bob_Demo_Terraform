# IBM Bob dev container

Open this configuration from IBM Bob's **Reopen in Container** command. Bob remains the host IDE
and uses the tools inside the container. The image includes Terraform development and security
utilities, while `.bob/mcp.json` starts the project MCP servers.

Export `TEAM_TFE_TOKEN`, `GITHUB_TOKEN`, and any required cloud credentials on the host before
creating the container. The setup script writes the HCP Terraform credential file only when the
token is present.

