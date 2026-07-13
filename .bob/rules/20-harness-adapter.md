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
| `Task` or “launch agent” | Use `spawn_subagent`; choose `explore` for read-only research and `general` when files must be written. |
| parallel foreground Task calls | Spawn independent subagents together, wait for completion, then verify their files with `glob`. |
| `$ARGUMENTS` | Use the complete argument text supplied after the Bob slash command. |

All 20 specialist role definitions are loaded explicitly as `50-agent-*.md` rules. When a skill
names a role, use the already-loaded definition and include its role, constraints, required output
format, requested FEATURE path, and specific scope in the subagent prompt. Subagents must persist
the artifacts required by the skill. Do not depend only on a returned summary.

Activate skills with Bob's native skill tool. Skill activation loads the complete instruction body
and its packaged executable/supporting assets. If an active skill requires another named skill,
activate it before continuing. Custom commands identify the top-level skill to activate.
