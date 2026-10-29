# Components: hooks & skills

The harness ships **hooks** (run by the environment) and **skills** (invoked by the model). Five
hooks are toggled per project in `.claude/harness.json`; the auto-bootstrap hook has no toggle (it
runs before any config exists). Skills come with the plugin.

## Hooks

### Auto-bootstrap (`harness_bootstrap`) — SessionStart hook
Closes the "installed but does nothing" gap: a plugin has no install-time hook, so the first session
in a project with **no** `.claude/harness.json` is where the harness configures itself. It detects the
stack (Rails/Node/Python/Go/generic) and writes a config with all components on and the gates in
**warn** mode, then announces it in the banner. It **never clobbers** an existing config (no-op if the
file is present), only runs inside a git repo, and writes `.claude/harness.json` alone — never
committed `settings.json`. No component toggle (it runs before config exists); opt out with the
`HARNESS_NO_AUTOBOOTSTRAP=1` environment variable. Configure deliberately instead with `/harness:init`.

### SessionStart banner (`session_banner`)
Prints an environment-verified status line at the start of every session — the active config home's
global ruleset, the harness config + stack, and your BYO agent count. Its whole point is to report
*reality* rather than what the model remembers. Shown unless `components.session_banner` is `false`.

### Skill nudge (`skill_nudge`) — SessionStart hook
Skills are **listed, not auto-applied**: at session start Claude Code registers them (availability),
but a skill's instructions only take effect once it's invoked (activation). Without a prompt the
operator has to type `/harness:<name>` before a skill shapes the response. This hook injects a
directive so the model invokes the right skill *on its own* the moment a trigger fires — `guardrails`
(each playbook's trigger: before a first edit, on a failed command, before claiming done, on a
language trap, calling a path live or sizing its cost, concluding code is wrong or planning on
external behavior, following existing code as the pattern, planning or adding beyond the ask),
`product-manager` (deciding
what's next / triaging / routing ready work), `story-writer` (writing or refining a story). It changes
model behavior only; a hook cannot call a skill itself.

Fires once per session at `SessionStart` with the **full** directive. (It previously also fired a
terse reminder on every `UserPromptSubmit`; that was dropped — the per-prompt injection added up over
a long session, and the SessionStart directive plus the auto-listed skills carry the reminder.) Shown
unless `components.skill_nudge` is `false`.

### Context warning (`context_warning`) — UserPromptSubmit hook
Almost all token spend is cache reads, so every turn costs roughly the size of the context, and a
long session re-reads everything it has built up on every call. On each prompt this hook reads the
live context size from the transcript (the last main-thread call's input, cache-creation and
cache-read tokens) and warns **once** at each step: **100K, 150K and 250K tokens**. The steps are
fixed token counts rather than a share of the window, because cost tracks context size: on a 1M
window a percentage step stays quiet until 750K, long after turns got expensive. You see a one-line
`systemMessage` with the context size; the model gets `additionalContext` saying this is information, not an
instruction to stop, and that it may suggest `/session-end`, `/clear`, `/session-start` at a natural
break. A step re-arms if context drops back below it (after `/compact`); `/clear` starts a new
session, so it starts fresh. Shown unless `components.context_warning` is `false`.

The steps are the first of: `$HARNESS_CONTEXT_STEPS` (a comma list), `context_warning.steps` in
`.claude/harness.json` (an array), then **100000, 150000, 250000**. Change them per user with
`HARNESS_CONTEXT_STEPS` (for example `80000,120000` in `settings.json` `env`), or for the whole team
in the project file. Each step must be a plain positive integer of at most nine digits; anything
else, including leading zeros, is dropped, and if none are left the defaults apply.

- A non-empty `HARNESS_CONTEXT_STEPS` with no valid entries still skips the
  `context_warning.steps` lookup, so the hook falls back to the defaults.

### Verification gate (`verification_gate`) — Stop hook
When a turn ends with implementation code changed (per `impl_dirs`), it **runs the project's
`test_command`** and **blocks** (`exit 2`) if it fails — a red test is a fact, not a judgment, so it
is safe to block on. It also **advises** (never blocks) when a UI/impl change (per `ui_dirs`) shipped
without a change under `operator_test_dir` — i.e. no operator-journey test. It short-circuits on
`stop_hook_active` so it can never loop. Inert unless `components.verification_gate` is `true`.

A `test_command` failure **blocks by default**. Rolling out gradually? `touch .claude/.verification-warn`
to downgrade to warn-only (the failure is surfaced but doesn't block). A Stop hook's `exit 2` prevents
the stop and continues so Claude addresses the gap.

**A pass has to test something.** If the command exits 0 but every test summary in its output reports
zero tests (`0 runs,` from Minitest, `0 tests,` from minitest-reporters, `0 examples,` from RSpec), the gate blocks as **UNVERIFIED — no
tests ran**: the command doesn't match the suite. Output with no summary line, or with any summary
above zero (a `bin/ci` whose system-test step is empty, say), passes as before. The check reads the
suite's whole log, not just the last 200 lines the gate shows.

**Which command, under which Ruby.** `test_command: "auto"` is resolved on every run (see
[configuration.md](configuration.md)). If the repo has a `.ruby-version` and mise already has that
Ruby installed (`mise where ruby@<version>`), the suite runs under `mise exec ruby@<version> --`,
because the hook inherits Claude Code's environment and that Ruby may not be the repo's. Otherwise
the command runs as written, so a Ruby managed by rbenv, chruby or asdf is left alone and mise never
installs anything inside the hook.

**One test run at a time.** The gate runs `test_command` through `tools/run_tests.sh`, which takes a
repo-wide lock in the git common dir, so every session and worktree of the repo shares it. Two
sessions ending a turn together no longer run the suite against the same test database at once; the
second waits for the first. A suite that runs past `stack.test_timeout_sec` (default 600) is killed
with everything it spawned. The wait is capped by `stack.test_lock_wait_sec` (default 600), and both
are trimmed to fit inside the Stop hook's 1800s timeout. When the suite didn't actually run (lock held
too long, timeout, bad settings), the gate blocks as **UNVERIFIED** or **SETUP ERROR**, never a silent
pass. To run the suite by hand under the same lock: `tools/run_tests.sh -- bin/ci`.

**Review layer (`components.review_gate`, opt-in, default off).** When on, the same Stop hook also
requires a **verified blind-review artifact** for the current diff: the `blind-review` skill writes
`.claude/.review/current.json`, and `tools/review_verify.sh` refuses it unless its `diff_sha` matches
the current tree and every finding cites a `file:line` actually in the diff (so a hand-written green
result can't satisfy it). `verdict: changes-requested` or a missing/stale artifact **blocks**;
`.claude/.verification-warn` downgrades it.

The artifact also records `base`, the full sha of `HEAD` at review time. With it, the checker renders
the current tree against `base` rather than against the uncommitted diff, so committing the reviewed
work (in one commit or several) keeps the artifact fresh, while any edit after the review, committed
or not, makes it stale. Findings are checked against the same base-relative diff, so they still
validate after the commit. An artifact without a full-sha `base` is checked the old way: it is fresh
only while the reviewed changes are uncommitted. This replaces the old `.claude/.last-review` check, which
compared a model-written marker to HEAD and couldn't tell a real review from a claimed one.

### Pipeline gate (`pipeline_gate`) — PreToolUse hook
Before an `Edit`/`Write` to the implementation surface (`impl_dirs`), it requires either:
- a story at `.claude/current-story.yaml` that PASSES the DoR lint (`dor_lint` exit 0 — the gate runs it; the verdict is computed, not a self-written stamp), or
- `.claude/.small-fix` (an explicit, surfaced escape hatch for genuinely independent small work).

Tests, config, docs, and `.claude/` are never gated. **Warn** by default (advises without deciding —
it never auto-approves the edit); `touch .claude/.pipeline-block` to **block**. Inert unless
`components.pipeline_gate` is `true`.

### Guardrails gate (`guardrails_gate`) — PreToolUse hook
The first edit in a session (or in a subagent) waits until the `guardrails` skill is loaded. If the
transcript has no `guardrails` Skill call, the first `Edit`/`Write`/`MultiEdit`/`NotebookEdit`, or
the first Bash command that writes files (`sed -i`, a redirect, `cp`/`mv`/`rm`, a script write), is
**denied** with a reason telling the agent to load the skill and run CODE. Retrying the edit without
loading the skill is denied again, up to **three times** per session or subagent; the fourth attempt goes
through, so an agent that can't load the skill is never stuck. (A single deny wasn't enough: Haiku 5.5
retried straight through it in 4 of 29 bench runs.) The gate notices the skill load from the `Skill` call itself, so it
works in headless runs with no saved transcript (`claude -p --no-session-persistence`).

Why it exists: in harness-bench runs, a third of agents never loaded guardrails despite the
SessionStart nudge. They edited through `sed -i` and heredocs, where no file-tool hook fires, and
they were the runs that took the bait. **On** by default; set `components.guardrails_gate` to `false`
to turn it off.

> Both gates read the *stack profile*, so "implementation surface" and "operator test" mean whatever
> your stack says — see [configuration.md](configuration.md).

## Skills

Skills come with the plugin (no per-project toggle) and are stack-agnostic. They are **listed, not
auto-applied** — Claude Code registers each skill's name + description at session start, but a skill's
instructions only take effect when it's invoked (via the `Skill` tool or a `/harness:<name>` command).
The `skill_nudge` hook (above) is what makes the model reach for the matching skill on its own instead
of waiting to be asked.

### `guardrails`
A routing table plus eight reference playbooks. Read the one whose trigger just fired; cite a fired
item's ID with one line of evidence.

| Trigger | Playbook |
|---|---|
| first edit of a file this session (C0: a change someone sees is traced from its entrypoint first; a ticket's "X builds this" is a claim) | CODE |
| dates/times, float money, async, sort, division, regex, mutation, closures | TRAPS |
| a failed command/test, a traceback, output contradicting a prediction | DEBUG |
| about to claim done / commit / open a PR | VERIFY |
| calling a path live, blaming a prod symptom, sizing cost | RUNTIME |
| concluding code is dead/wrong, or planning on external-system behavior | MECHANISM |
| naming existing code as the pattern to follow, or adding new behavior to existing code in its style | PRECEDENT |
| planning/delegating, adding an abstraction/option/dependency/file, or a diff wider than the ask | SCOPE |
| surfacing a problem that isn't the current task | VERIFY (V13) — file it as a card and a backlog entry, without asking |

### `story-writer`
Turns a PRD / cited source / structured input into a Definition-of-Ready card. Its inviolable rule:
never invent a boundary — ground every value in the source, else existing code, else escalate as an
open question. Strips solutioning. Runs the deterministic DoR lint
(`ruby ${CLAUDE_PLUGIN_ROOT}/tools/dor_lint.rb <story>.yaml`) and quotes the verdict; a card is READY
only when the lint exits 0.

### `product-manager`
Prioritizes from real signals (never invented) and drives the pipeline: prioritize → ready (via
story-writer) → record `.claude/current-story.yaml` (which the pipeline gate lints to unlock) → route to an
engineer (BYO agent) → track. Coordinates gates; never bypasses them. Acts on the board with operator
authority (triage, move, tag, pin, assign, comment — never delete).

**Tracker:** the harness ships with **Fizzy** as the default board MCP (both skills use
`fizzy_*` read/act tools, with the delete operations withheld by design). It's a default, not a
requirement — point the operations at whatever tracker MCP your project uses, or run the pipeline
against a file-backed backlog (`stories/` + `.claude/current-story.yaml`) with no tracker at all.

### `bookshelf`
Reads your own reference books (EPUBs) in place via `${CLAUDE_PLUGIN_ROOT}/tools/tome.sh`, so a
design/idiom/convention call can be grounded in — and quote — a primary source instead of memory.
Books are **BYO and never shipped** (copyright); point the reader at your shelf with `TOMES_DIR`
(the installer's user step can set it). **Fails gracefully when no shelf exists:** if `TOMES_DIR` is
unset and the fallback shelves are empty, or a book isn't found, the skill says so and falls back to
live docs or an explicit "unverified" label — it never blocks and never invents a book's contents.
Agents can invoke this skill too (see [agents.md](agents.md) → the bookshelf directive).

### `blind-review`
Produces an independent, **blind** review of the current diff and writes the findings artifact the
verification gate's review layer checks (`.claude/.review/current.json`). Blind = the reviewer sees the
diff, the rules, and ground-truth, but **not** the card/conversation/intent that produced the code —
the framing that would prime it to rationalize the mistake. It delegates to your project's reviewer
(BYO; Rails → `dhh-code-reviewer`), then records structured findings that `tools/review_verify.sh`
re-checks against the diff. Load it when `review_gate` is on, or any time you want a verified review.

## How they fit together

```
SessionStart banner ─ reports state
        │
story-writer → DoR lint → product-manager ─ writes .claude/current-story.yaml (dor_lint: PASSED)
        │                                          │
        │                                    unlocks
        ▼                                          ▼
   guardrails ──── loaded at each risk point ── your BYO agents implement
        │                                          │
        ▼                                          ▼
 pipeline gate (before edits)          verification gate (at Stop) → review + operator test
```
