---
description: Set up or reconfigure the harness for this project — detects the stack, writes .claude/harness.json, and (unless --local/--no-plugin) enables the plugin for the team.
---

Set up the harness in the current project by running the bundled installer non-interactively.

Run this, passing through any arguments the user supplied (`$ARGUMENTS`):

```
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" --yes $ARGUMENTS .
```

With no arguments the installer auto-detects the stack (Rails/Node/Python/Go/generic), activates all
components with the gates in **warn mode**, and enables the plugin in the project's committed
`.claude/settings.json`. Common overrides the user may pass through `$ARGUMENTS`:

- `--stack <name>` — force a stack instead of auto-detect
- `--components a,b` — only these components (`session_banner,skill_nudge,context_warning,verification_gate,pipeline_gate`)
- `--local` — enablement in `.claude/settings.local.json` (just this developer) instead of committed
- `--no-plugin` — only write `.claude/harness.json`, don't touch settings

After it runs, tell the user which stack was detected and what was written, and remind them they can
pull in their stack's agents with `/harness:agents`.
