# harness

**A stack-agnostic engineering harness for Claude Code.** It turns Claude Code into a disciplined
teammate — enforcement hooks, guardrail playbooks, and a product-management delivery pipeline —
and it works for *any* stack because it's driven by a small per-project config. You **bring your
own agents**; the harness supplies the mechanism.

```sh
git clone https://github.com/octanelabsdev/harness ~/harness
~/harness/install.sh /path/to/your/project      # interactive: pick your stack + components
```

That's it. Restart Claude Code in your project and the harness is live.

---

## Why this exists

Left alone, an AI coding agent forgets the rules it was told, claims "done" without running
anything, edits the wrong file, and drifts from your conventions. A **harness** is the scaffolding
that holds it to a standard:

- a **SessionStart banner** that reports *environment-verified* state (not the model's memory),
- a **verification gate** that won't let a turn end claiming success without evidence,
- a **pipeline gate** that keeps feature work flowing through a Definition-of-Ready story,
- **guardrails** — short checklists the model reads at the exact moment a known mistake is about
  to happen,
- a **PM pipeline** (story-writer → DoR gate → product-manager) so work is ready before it's built.

Most harnesses are welded to one framework. This one isn't: every stack-specific detail lives in a
**stack profile** you pick at install time, so the same hooks work for Rails, Node, Python, Go, or
anything you describe.

## The mental model: mechanism vs. payload

| | Where it lives | You get it by |
|---|---|---|
| **Mechanism** — hooks, guardrails, PM pipeline | this repo (a Claude Code **plugin**) | `install.sh` / `/plugin` |
| **Stack profile** — impl dirs, test dir, test command | `.claude/harness.json` in your project | `install.sh` writes it |
| **Agents** — your specialists | your project's `.claude/agents/` (**BYO**) | you drop them in |

The harness ships **zero agents**. Bring your own — or use an example bundle like
[octanelabsdev/rails-agents](https://github.com/octanelabsdev/rails-agents) for Rails.

## What's inside

- **Hooks** (`hooks/`) — `harness_bootstrap` (auto-writes `.claude/harness.json` on first session),
  `session_start_banner`, `skill_nudge`, `verification_gate`, `pipeline_gate`. Portable
  (`${CLAUDE_PLUGIN_ROOT}`), config-driven (the two informational hooks default on; the enforcing
  gates default off — when on, the pipeline gate warns, the verification gate blocks on a failing
  `test_command`, and its opt-in `review_gate` blocks unless a verified blind-review artifact exists).
- **Commands** (`commands/`) — `/harness:init` ((re)configure a project via the installer),
  `/harness:agents` (bring your stack's agent bundle into `.claude/agents/`), `/harness:status`
  (inventory of what's loaded/configured), `/harness:doctor` (health check — exits non-zero on a gap),
  and `/harness:update` (check for / move to a newer release tag).
- **Skills** (`skills/`) — `guardrails` (6 playbooks: CODE, DEBUG, VERIFY, TRAPS, RUNTIME,
  MECHANISM), `story-writer`, `product-manager`, `bookshelf`, `blind-review`. Model-invoked, stack-agnostic — skills
  are **listed, not auto-applied** (availability ≠ activation), so the `skill_nudge` hook prompts the
  model to invoke the matching one on its own trigger instead of waiting for a `/command`.
- **Stacks** (`stacks/`) — presets: `rails`, `node`, `python`, `go`, `generic` (+ custom).
- **Installer** (`install.sh`) — interactive or flag-driven; auto-detects your stack.
- **Template** (`templates/global-CLAUDE.md`) — a generic starter ruleset for your config home.

## Installing

Two ways to get the harness. Both give you the same plugin.

### A. From the marketplace (native Claude Code)

Add this repo as a plugin marketplace, then install the plugin:

```sh
/plugin marketplace add octanelabsdev/harness
/plugin install harness@harness
```

Or wire it into a project's `.claude/settings.json` (committed, and **pinned** to a release tag so
the plugin code can't shift under you):

```jsonc
{
  "extraKnownMarketplaces": {
    "harness": { "source": { "source": "github", "repo": "octanelabsdev/harness", "ref": "v0.2.2" } }
  },
  "enabledPlugins": { "harness@harness": true }
}
```

> **Installing the plugin is enough to start.** On the first session in a project with no
> `.claude/harness.json`, the harness **auto-bootstraps** one: it detects your stack (Rails/Node/
> Python/Go/generic) and writes a config with all components on and the gates in **warn** mode, then
> says so in the banner. Run `/harness:init` any time to (re)configure it properly (force a stack,
> pick components, enable it for the team), and `/harness:agents` to pull in your stack's agent bundle.
> Opt out of auto-bootstrap with `HARNESS_NO_AUTOBOOTSTRAP=1`. (You can still hand-write
> `.claude/harness.json` — see [docs/configuration.md](docs/configuration.md).)

### B. With the installer (does everything)

The installer sets up the parts the plugin can't — `.claude/harness.json`, pinned plugin enablement,
`.mcp.json`, `TOMES_DIR` — interactively:

```sh
git clone https://github.com/octanelabsdev/harness ~/harness
~/harness/install.sh /path/to/your/project        # interactive: stack + components
~/harness/install.sh --stack rails --yes .        # non-interactive
```

Moving a repo off a pre-plugin install? Add `--migrate` (dry-run) / `--migrate --apply` to clean the
old committed hooks/settings/symlinks first. Full detail: [docs/install.md](docs/install.md).

## 60-second tour of a configured project

After `install.sh`, your project has:

```jsonc
// .claude/harness.json   (committed — your team shares it)
{
  "components": { "session_banner": true, "skill_nudge": true, "verification_gate": true, "pipeline_gate": true },
  "stack": {
    "name": "rails",
    "impl_dirs": ["app", "lib", "db/migrate"],
    "ui_dirs": ["app/views", "app/controllers"],
    "test_dir": "test", "operator_test_dir": "test/system",
    "test_command": "bin/rails test"
  }
}
```
```jsonc
// .claude/settings.json   (committed — safe: references the versioned plugin, not a $HOME script)
{ "extraKnownMarketplaces": { "harness": { "source": { "source": "github", "repo": "octanelabsdev/harness" } } },
  "enabledPlugins": { "harness@harness": true } }
```

Open a session and the banner reports it:

```
HARNESS CHECK (SessionStart hook — environment-verified, not model memory):
  global CLAUDE.md : present (72 lines)
  harness          : configured (stack: rails; active: session_banner, skill_nudge, verification_gate, pipeline_gate)
  agents (BYO)     : 21 agent(s)
```

## Documentation

📖 **Full manual: [harness.octanelabs.dev](https://harness.octanelabs.dev/)** — the docs below, rendered and searchable.

- **[docs/concepts.md](docs/concepts.md)** — the architecture, the plugin+config split, the security model.
- **[docs/install.md](docs/install.md)** — install in depth: interactive, flags, scopes, CI, updating, uninstalling.
- **[docs/configuration.md](docs/configuration.md)** — `.claude/harness.json`, components, stack profiles (presets + custom).
- **[docs/components.md](docs/components.md)** — the four hooks and four skills, in detail; warn → block.
- **[docs/agents.md](docs/agents.md)** — bring-your-own agents: adding, overriding, authoring, the rails-agents example.
- **[docs/troubleshooting.md](docs/troubleshooting.md)** — FAQ and fixes.

## Maintaining / releasing

Two gates run before tagging a release. `claude plugin validate` passing is **not** sufficient — it
checks the manifest schema, not that shipped content is portable or that the plugin actually loads.

**1. Shipped-path guard.** The harness installs onto other people's machines, so shipped content must
never carry an author-local path (a personal vault, a real `/Users/<name>` home, a `~/Development`
bundle):

```sh
bash tools/check_shipped_paths.sh   # exits non-zero on any author-local path in tracked files
```

It scans every tracked file (a documented `/Users/you`-style placeholder is allowed, as is any line
carrying a `shipped-path-ok` sentinel).

**2. Load smoke test.** Proves the plugin actually loads — the duplicate-hooks bug that shipped in
0.1.0–0.1.2 passed both `validate` and `plugin details`; only a load exercise catches that class:

```sh
bash tools/smoke_load.sh   # static manifest hygiene + a live install into a throwaway config
```

It fails if the manifest re-declares the auto-loaded `hooks/hooks.json` (the duplicate-hooks bug), if
the hooks file is malformed, or if a throwaway install doesn't load the expected skills/hooks cleanly.
`--static-only` skips the live install (for machines without `claude`).

Wire both as a pre-push guard if you want them enforced automatically:

```sh
printf '#!/bin/sh\nbash tools/check_shipped_paths.sh && bash tools/smoke_load.sh --static-only\n' > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

## Requirements

Claude Code, plus `bash`, `git`, `jq`, and `python3`. (`ruby` if you use the story-writer's DoR lint.)

## License

MIT.
