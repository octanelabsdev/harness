---
name: guardrails
description: Engineering-discipline guardrails — short event-triggered checklists to run at known failure points. Load when creating or modifying code, debugging a failed command or test, before claiming work done or committing, when touching language traps (dates/times, float money, async, sort, division, regex, mutation, closures), when asserting a code path is live or sizing its cost/impact, or when concluding code is wrong/dead or planning on how an external system behaves. Stack-agnostic.
---

# Guardrails

Short, event-triggered playbooks that turn engineering discipline into paste-verified checklists.
The moment a trigger below fires, read the matching reference and follow its items. Cite an item's
ID with one line of evidence when it fires — **skipping a fired item is a violation.** Read only the
one reference the current moment calls for, not all of them.

| The moment you… | Read |
|---|---|
| create or modify a repo file for the first time this session | `references/CODE.md` |
| touch dates/times, float money, async, sort, division/modulo, regex, mutation-vs-copy, or closures-in-loops | `references/TRAPS.md` |
| hit a non-zero exit, a traceback, output contradicting your prediction, or a bug you haven't reproduced this session | `references/DEBUG.md` |
| are about to write "done / fixed / works / passing / complete", or run `git commit` / `gh pr create` | `references/VERIFY.md` |
| are about to call a code path live/running, blame it for a production symptom, or size its cost/impact/priority | `references/RUNTIME.md` |
| are about to conclude code is dead/wrong/removable, override a comment/doc/author, or build a plan on how an external system/API/framework behaves | `references/MECHANISM.md` |
| surface a problem that isn't the current task (a gap, stale data, a dead job, a bug next door) | `references/VERIFY.md` (V13) |

Each reference states its trigger in its opening line and lists IDed items with an echo protocol
(`PASS`/`FAIL`/`N/A`, each with quoted evidence). The playbooks are stack-agnostic; examples span
languages. They enforce the operational directives in your global ruleset — they don't replace them.
