# Components: hooks & skills

The harness ships **hooks** (run by the environment) and **skills** (invoked by the model). Four
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
(before a first edit / on a failed command / before claiming done), `product-manager` (deciding
what's next / triaging / routing ready work), `story-writer` (writing or refining a story). It changes
model behavior only; a hook cannot call a skill itself.

Fires once per session at `SessionStart` with the **full** directive. (It previously also fired a
terse reminder on every `UserPromptSubmit`; that was dropped — the per-prompt injection added up over
a long session, and the SessionStart directive plus the auto-listed skills carry the reminder.) Shown
unless `components.skill_nudge` is `false`.

### Verification gate (`verification_gate`) — Stop hook
When a turn ends with implementation code changed (per `impl_dirs`), it **runs the project's
`test_command`** and **blocks** (`exit 2`) if it fails — a red test is a fact, not a judgment, so it
is safe to block on. It also **advises** (never blocks) when a UI/impl change (per `ui_dirs`) shipped
without a change under `operator_test_dir` — i.e. no operator-journey test. It short-circuits on
`stop_hook_active` so it can never loop. Inert unless `components.verification_gate` is `true`.

A `test_command` failure **blocks by default**. Rolling out gradually? `touch .claude/.verification-warn`
to downgrade to warn-only (the failure is surfaced but doesn't block). A Stop hook's `exit 2` prevents
the stop and continues so Claude addresses the gap.

#### Test runs: one at a time
Two sessions (or two worktrees of one repo) ending a turn together would otherwise run the suite at
the same moment against the same test database and fail each other at random. The gate runs
`test_command` through **`tools/run_tests.sh`**, which takes a repo-wide lock first:

- **The lock** is a directory in the git common dir (`.git/harness-test.lock`), so every worktree
  shares it. A second run **waits** for the first instead of running alongside it.
- **Crashed runs don't wedge it.** A lock is cleared when its owner process is gone (same host), when no owner was
  recorded within 10s, or when it has outlived the owner's own timeout plus 120s.
- **Timeouts kill the whole suite**, including the processes it spawned, after `stack.test_timeout_sec`.
- **Output** goes to `.git/harness-test-run.log` (the gate shows its tail) so a daemon the suite
  left behind can't hold the gate open.
- **It always runs.** No result is cached or reused; a pass always comes from a real run.

The Stop hook's own timeout is 1800s. A hook that Claude Code kills renders no decision, which would
let the turn end silently, so the gate fits the lock wait and the run inside it. Every way the tests
can fail to give an answer **blocks** (subject to `.verification-warn`) with a distinct verdict:

| Verdict | Meaning |
|---|---|
| `test_command failed` | The suite ran and was red. |
| `UNVERIFIED — another test run held the lock …` | Another run held the lock past `test_lock_wait_sec`; the tests did **not** run. |
| `UNVERIFIED — test_command exceeded …` | The suite ran past `test_timeout_sec` and was killed. |
| `SETUP ERROR — tests did NOT run …` | Bad timeout/wait values, or the lock can't be created (e.g. read-only `.git`). |

**Running the suite by hand?** Take the same lock, so your run and a session's gate queue instead of
colliding:
```sh
# the newest installed harness (CLAUDE_PLUGIN_ROOT is only set for hooks, not your shell)
H=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/harness/harness/*/ | sort -V | tail -1)
bash "${H%/}/tools/run_tests.sh" -- bin/ci
bash "${H%/}/tools/run_tests.sh" --timeout 900 --wait 300 -- bin/rails test
```
Run it from inside the repo. Exit codes: `0` green, `1` red, `2` usage/setup error, `3` busy (not
run), `4` timed out. From a terminal, output streams live instead of going to the log.

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

> Both gates read the *stack profile*, so "implementation surface" and "operator test" mean whatever
> your stack says — see [configuration.md](configuration.md).

## Skills

Skills come with the plugin (no per-project toggle) and are stack-agnostic. They are **listed, not
auto-applied** — Claude Code registers each skill's name + description at session start, but a skill's
instructions only take effect when it's invoked (via the `Skill` tool or a `/harness:<name>` command).
The `skill_nudge` hook (above) is what makes the model reach for the matching skill on its own instead
of waiting to be asked.

### `guardrails`
A routing table plus six reference playbooks. Read the one whose trigger just fired; cite a fired
item's ID with one line of evidence.

| Trigger | Playbook |
|---|---|
| first edit of a file this session | CODE |
| dates/times, float money, async, sort, division, regex, mutation, closures | TRAPS |
| a failed command/test, a traceback, output contradicting a prediction | DEBUG |
| about to claim done / commit / open a PR | VERIFY |
| calling a path live, blaming a prod symptom, sizing cost | RUNTIME |
| concluding code is dead/wrong, or planning on external-system behavior | MECHANISM |

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
