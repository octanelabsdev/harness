# Concepts & architecture

The harness is four layers of scaffolding plus a delivery pipeline. Each works on its own and gets
stronger in combination.

## The layers

1. **The stack profile** (`.claude/harness.json`) — a tiny per-project config that names your
   implementation directories, test directory, operator/e2e test directory, and test command, and
   toggles which components are active. Everything stack-specific lives here, which is what lets one
   set of hooks serve any framework.

2. **Hooks** (a Claude Code plugin) — shell the *environment* runs, not the model, so they report
   reality:
   - **SessionStart banner** — prints environment-verified state (config home's global ruleset,
     harness config + stack, and your BYO agent count).
   - **Stop verification gate** — when a turn ends with implementation code changed, runs the test
     command and blocks on a red (or unanswered) result; advises when a UI change lacks an
     operator-journey test; optionally requires a verified blind review.
   - **PreToolUse pipeline gate** — before an edit to the implementation surface, requires a
     Definition-of-Ready story (or an explicit small-fix escape hatch).

3. **Guardrails** (a skill) — six short, event-triggered playbooks the model reads the moment a
   known failure pattern is about to happen: `CODE` (before the first edit), `DEBUG` (a failed
   command), `VERIFY` (before claiming done), `TRAPS` (language footguns), `RUNTIME` (asserting a
   path is live/costly), `MECHANISM` (concluding code is wrong or planning on external behavior).

4. **The PM pipeline** (two skills + a lint) — `story-writer` turns a requirement into a
   Definition-of-Ready card (never inventing boundaries; running a deterministic DoR lint), and
   `product-manager` prioritizes from real signals and stamps the token that authorizes the build.

Riding on top: **your agents** (BYO), which the harness is deliberately agnostic about.

## Plugin + config: why the split

Claude Code plugins install wholesale and are portable (they reference `${CLAUDE_PLUGIN_ROOT}`, not
absolute paths). That's perfect for the *mechanism*. But a plugin can't know your stack, can't ask
you which components you want, and can't ship a global ruleset. So:

- **The plugin** carries the hooks and skills — the same for everyone.
- **`.claude/harness.json`** carries the per-project choices — the hooks read it at runtime, so the
  plugin behaves differently per project without any per-project code.
- **The installer** does the interactive selection, writes the config, enables the plugin, and
  (optionally) drops a generic global ruleset.

A hook with no `harness.json` is **inert** — installing the plugin never intrudes until a project
opts in via config.

## Config-driven, not framework-coded

The gates never hardcode `app/` or `test/system/`. They read `impl_dirs`, `ui_dirs`,
`operator_test_dir`, and `test_command` from the stack profile. The **same** `pipeline_gate.sh`
gates `app/` on Rails and `src/` on Node; the **same** `verification_gate.sh` tells a Rails dev to
add a `test/system/` test and run `bin/rails test`, and a Node dev to add an `e2e/` test and run
`npm test`. New stack? Add a preset or answer the installer's custom prompts.

## The security model (why enablement is committed but safe)

The old anti-pattern was committing a `settings.json` whose hooks ran
`bash "$HOME/…/some-script.sh"` — every teammate who checked out the repo auto-ran unversioned,
out-of-repo code. The plugin model fixes this:

- What you commit is `extraKnownMarketplaces` + `enabledPlugins` — a reference to a **versioned,
  marketplace-distributed plugin** (installed to the plugin cache, reviewable), not a path to a
  script on someone's disk.
- Hooks inside the plugin reference `${CLAUDE_PLUGIN_ROOT}` — resolved by Claude Code, never a
  personal `$HOME` path.
- So committing the harness to a shared repo is safe and team-wide. Prefer `--local` (writes
  `settings.local.json`) if you want the harness only on your machine.

## Config homes (personal vs. work)

Everything respects `CLAUDE_CONFIG_DIR`. The banner reports the *active* config home's global
ruleset; the plugin cache lives under the active home; project config (`harness.json`,
`settings.json`) is the same regardless of which home opened the repo. Personal (`~/.claude`) and
work (`~/.claude-work`, selected via `CLAUDE_CONFIG_DIR`) never cross-read.

## Warn first, block when proven

Deterministic checks block; judgment advises. The verification gate **runs your `test_command` and
blocks on a red result** — a failing test is a fact — while its operator-test reminder only advises.
The pipeline gate ships in **warn** mode (it advises without ever auto-approving the edit); promote it
with `touch .claude/.pipeline-block` where drift proves costly, and downgrade the verification gate to
warn-only with `.claude/.verification-warn` while rolling out. The real lever isn't the gate — it's
making the right path (the PM pipeline) the path of least resistance, so the gate rarely fires.

The **review gate** (opt-in `components.review_gate`) is the judgment layer done honestly: a Stop hook
can't run a reviewer, so instead of trusting "I reviewed it," it requires a **blind-review artifact** for
the exact current diff (written by the `blind-review` skill, verified by `tools/review_verify.sh` against
the diff — a finding must cite a real changed line, so a hand-written green can't pass). Enforce what a
machine can check (a red test, a stale/absent artifact); let the reviewer's *judgment* be loud and
human-visible rather than a self-written green stamp.
