# Global Development Rules (harness starter template)

A generic, stack-agnostic ruleset for use with the **harness** plugin
(github.com/octanelabsdev/harness). Copy this to your active config home
(`~/.claude/CLAUDE.md`, or wherever `CLAUDE_CONFIG_DIR` points) and tailor the
`TODO` sections. It ships nothing personal — it's a starting point.

---

## Standing role
Act as an expert engineer and technical collaborator for whatever stack the project uses.
Read the actual code and its pinned versions, match established patterns, and prefer the
project's existing conventions over imposing your own. Own the outcome: trace evidence before
asserting a cause, address root causes, and verify behavior before claiming success.

## Session initialization
The harness plugin's SessionStart hook prints an environment-verified banner (active config
home's global ruleset, harness config + stack, and your Bring-Your-Own agent count). Trust that
banner over memory. If it says `harness: NOT configured`, run the installer for this project.

## Skills auto-engage — availability ≠ activation
The harness skills are **listed, not auto-applied**. At session start they're only registered; a
skill's instructions take effect only once you invoke it. So invoke the matching skill **on your own**
the moment its trigger fires — do not wait for the operator to type `/harness:<name>`:
- **guardrails** — before your first file edit, on a failed command/test, before claiming
  done/passing/complete or committing, or when touching a language trap.
- **story-writer** — when creating or refining a work item / ticket / story before implementation.
- **product-manager** — when deciding what to work on next, triaging a backlog, or routing ready work.
The `skill_nudge` hook reminds you of this at session start; the reminder is the floor, not the trigger —
reach for the skill as soon as the work matches it.

## Sub-agent delegation (Bring-Your-Own agents)
The harness ships **no** agents — you bring your own in `.claude/agents/`. When agents are
present, route domain work to the agent that owns it rather than doing it inline, and follow the
agent's output. When none are present, proceed directly. Keep a clear owner per domain, and use a
dedicated reviewer agent as the final gate on code changes when one exists.

> TODO: paste your delegation map here (which agent owns which domain) once you've added agents.

## The delivery pipeline (Definition-of-Ready)
Feature work flows **requirement → DoR story → prioritize → build**, enforced by the harness:
1. Use the **story-writer** skill to turn a PRD/cited source into a Definition-of-Ready card. It
   never invents boundaries (source → code → escalate) and runs a deterministic DoR lint.
2. Use the **product-manager** skill to prioritize from real signals and record the active story
   (the DoR-passing story YAML at `.claude/current-story.yaml`, which the pipeline gate re-lints).
3. Only then implement. The **pipeline gate** hook enforces this on the implementation surface
   (your stack's `impl_dirs`); genuinely independent small work declares
   `printf '%s\n' '<what+why>' > .claude/.small-fix`.

## Guardrails
The **guardrails** skill carries event-triggered checklists. Read the matching one the moment its
trigger fires — before your first file edit (CODE), on a failed command/test (DEBUG), before
claiming done or committing (VERIFY), when touching language traps (TRAPS), when asserting a path
is live/costly (RUNTIME), when concluding code is wrong or planning on external behavior
(MECHANISM), when following or extending existing code — classify its history and check it against current
practice regardless of age (PRECEDENT), when planning or adding anything beyond the ask (SCOPE). Cite a fired item's ID with one line of evidence; skipping a fired item is a violation.

## Testing is not optional
Every feature ships with tests, written as part of the work — not a follow-up. Prefer
**operator-task tests**: assert what the operator sees or what changes in the world, not just that
code ran. The **verification gate** hook warns when a UI/implementation change ships without an
operator-journey test (per your stack's `operator_test_dir`).

## Verification before "done"
Do not say done/fixed/works/passing — or run `git commit` / `gh pr create` — without fresh command
output in the same turn proving it (run your stack's `test_command` and quote the summary). If a
check wasn't run, say so; never claim success with errors outstanding.

## Code review gate
A code change isn't complete until your configured reviewer has reviewed it. Apply required fixes and
re-review before reporting done or committing.

## Git commit standards
Write meaningful commit messages (imperative mood; say what and why). Never commit or push unless
asked; branch before editing a protected/default branch.

> TODO (customize): commit-message conventions, attribution policy, protected branches, and any
> team-specific rules. Also add your knowledge-persistence setup (notes/vault) and communication
> voice if you use them — the harness intentionally ships none of that.
