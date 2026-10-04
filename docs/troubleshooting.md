# Troubleshooting & FAQ

## The banner says `harness: NOT configured`
There's no `.claude/harness.json` in the project (or you're above the repo root). Run
`~/harness/install.sh .` in the project. The plugin can be enabled but the enforcing gates stay
inert until the config exists — that's by design.

## The banner doesn't appear at all
- The plugin isn't picked up yet — **restart Claude Code** (or run `/config` once) after installing.
- Confirm it's enabled: `claude plugin list` should show `harness@harness … enabled`.
- Confirm the marketplace is known: `claude plugin marketplace list`.

## `claude plugin install` / `marketplace add` can't find it
The marketplace is the public repo. Use `octanelabsdev/harness` (GitHub shorthand) or the full URL.
Behind a proxy/firewall, ensure github.com is reachable.

## Gates aren't firing
- Check `.claude/harness.json` → `components`: the gate must be `true`. The two gates default **off**
  when unconfigured.
- Check the path you edited is under `stack.impl_dirs` — only the implementation surface is gated.
- Confirm `jq` is installed (the hooks parse config with it).

## The verification gate never mentions operator tests
That check needs both `stack.ui_dirs` (non-empty) and `stack.operator_test_dir` (non-empty). Stacks
with no UI layer (e.g. `generic`, `go`) intentionally skip it. Also note: git collapses a fully
*untracked* directory to one entry (`app/`), which can hide file-level granularity — commit a
placeholder so new files show individually.

## Hooks seem to fire twice
You probably have hooks in **both** a committed `settings.json` *and* the plugin (or an old
`$HOME`-path hook left behind). Remove the old `"hooks"` block from `settings.json`; the plugin
provides them. (This is exactly the migration the harness replaces — see the project's cleanup notes.)

## A teammate checked out the repo and nothing happened
Enabling a plugin per-project takes effect when they **trust the folder** and restart. If you used
`--local`, the enablement is in your gitignored `settings.local.json` and teammates won't get it —
use project scope (default) for team-wide, or have each teammate run `install.sh`.

## `${CLAUDE_PLUGIN_ROOT}` shows up literally
It's substituted by Claude Code in plugin **content** (skills/agents) and set as a real env var for
**hook processes** — but it is *not* expanded in ad-hoc Bash you run yourself. If you're testing a
hook by hand, run it as Claude Code would (it sets the variable), or substitute the path manually.

## Work vs. personal configs are mixing
The harness honors `CLAUDE_CONFIG_DIR`. Launch work sessions with your work config
(e.g. `CLAUDE_CONFIG_DIR=~/.claude-work claude`) — the banner will report the *work* global ruleset,
and the plugin cache/config stay under that home. The two never cross-read.

## Agents show as `BROKEN` in the banner
Broken symlinks in `.claude/agents/` — usually a bundle moved or an agent was renamed/removed.
Re-link them (see [agents.md](agents.md)).

## I want the gates to actually block, not warn
- Pipeline gate: `touch .claude/.pipeline-block`.
- Verification gate: edit `hooks/verification_gate.sh` per the note at its tail (swap `exit 0` for
  `exit 2` when warnings exist). Promote only after the warn phase is quiet on false positives.

## The `rails` MCP server won't connect (`-32602 Unsupported protocol version`)
On a **legacy Rails app** the installer's in-bundle MCP setup pins a dead version of the server. The
installer writes `.mcp.json` with `bundle exec rails-mcp-server` and adds `gem "rails-mcp-server"` to
the Gemfile — but on an old app (e.g. Rails 7.0 / rack 2.2) bundler can only resolve rails-mcp-server
**1.0.1**, because every protocol-compatible release (1.2.0+ switched to `fast-mcp`; 1.6.1/2.0.0 need
newer `activesupport`) conflicts with the app's locked deps. 1.0.1 → `mcp-rb 0.3.2` speaks **only** MCP
protocol `2024-11-05` and *hard-rejects* the newer version Claude Code offers instead of negotiating
down — so the handshake dies with `-32602`.

**Don't** try the mise shim (`~/.local/share/mise/shims/rails-mcp-server`) as a fix: it's
cwd-sensitive and, launched from the project dir, resolves to the same broken in-bundle 1.0.1 (its
`version` output from `$HOME` is misleading).

**Fix — run it standalone, by absolute path.** rails-mcp-server is a standalone tool: it reads
`~/.config/rails-mcp/projects.yml` and introspects by shelling into the target app's own `bin/rails`,
so it never needs to be in the app bundle. Install a current version outside the bundle
(`gem install rails-mcp-server` under a modern Ruby, or via mise global) and point `.mcp.json` at it
directly:

```json
{ "mcpServers": { "rails": {
  "command": "/absolute/path/to/rails-mcp-server",
  "args": ["--mode", "stdio"]
} } }
```

2.0.0 (fast-mcp) negotiates the handshake and Claude Code connects (after a restart). Then remove
`gem "rails-mcp-server"` from the app Gemfile. **Installer TODO:** stop adding the gem in-bundle and
stop using `bundle exec` — detect a standalone install and reference its absolute path instead.

## Validate a change to the harness itself
```sh
claude plugin validate . --strict
```
Runs the marketplace/plugin/skill checks. Use `--strict` in CI to fail on warnings.
