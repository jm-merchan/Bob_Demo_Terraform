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

Agent role prompts live in `.bob/agents/`. Before spawning a role named by a skill, read the
matching `.bob/agents/<role>.md` and include its role, constraints, requested FEATURE path, and
specific scope in the subagent prompt. Subagents must persist the artifacts required by the skill.
Do not depend only on the subagent's returned summary.

Skills are stored in `.bob/skills/` and should be activated with Bob's skill tool. If a skill asks
for another named skill, activate that skill before continuing. Custom commands already identify
the top-level skill to use.

