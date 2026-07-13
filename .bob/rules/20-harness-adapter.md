# IBM Bob harness adapter

The imported skills are agent-harness neutral in intent but retain some legacy tool vocabulary.
Interpret it as follows when running in IBM Bob:

| Skill wording | IBM Bob behavior |
| --- | --- |
| `AskUserQuestion` | Use Bob's follow-up question tool. |
| `Read` | Use `read_file`. |
| `Glob` | Use `glob`. |
| `Grep` | Use `grep`. |
| `Bash` | Use `execute_command`. |
| `Task` or "launch agent" | Use `spawn_subagent`; choose `explore` for read-only research and `general` when files must be written. |
| parallel foreground Task calls | Spawn independent subagents together, wait for completion, then verify their files with `glob`. |
| `$ARGUMENTS` | Use the complete argument text supplied after the Bob slash command. |

Specialist role definitions live in `.bob/skills/<name>/SKILL.md` and are loaded on-demand via
`spawn_subagent` (using the agent `name` field). They are NOT pre-loaded into the orchestrator
context. When a workflow skill names a role (e.g., `tf-module-research`, `tf-module-developer`),
pass the role's `name` string to `spawn_subagent` and include the FEATURE path and specific scope
in the description. Subagents read their own design/research files from disk — do not relay file
contents through the orchestrator context.

Activate workflow skills with Bob's native skill tool. Skill activation loads the complete
instruction body and its packaged executable/supporting assets. If an active skill requires another
named skill, activate it before continuing. Custom commands identify the top-level skill to activate.
