# Configuration: `.claude/harness.json`

The harness is config-driven. One file per project — `.claude/harness.json` — declares which
components are active and describes your stack. The hooks read it at runtime; with no file, the
enforcing gates stay inert.

## Schema

```jsonc
{
  "components": {
    "session_banner":    true,   // SessionStart status banner (informational; default shown)
    "skill_nudge":       true,   // SessionStart nudge to invoke skills (default on)
    "context_warning":   true,   // UserPromptSubmit warning at 75/85/95% of the context window (default on)
    "verification_gate": true,   // Stop gate — runs test_command; blocks on failure
    "pipeline_gate":     true,   // PreToolUse gate — DoR story required for feature edits
    "guardrails_gate":   true,   // PreToolUse — first edit waits for the guardrails skill, denied once (default on)
    "review_gate":       false   // Stop gate — require a verified blind-review artifact (opt-in, default off)
  },
  "context_warning": { "window": 1000000 },     // optional: context window in tokens for the warning steps
  "stack": {
    "name": "rails",                            // label, shown in the banner
    "impl_dirs":  ["app", "lib", "db/migrate"], // the "implementation surface" the gates care about
    "ui_dirs":    ["app/views", "app/controllers"], // subset whose change should ship an operator test
    "test_dir":   "test",                       // where unit/integration tests live
    "operator_test_dir": "test/system",         // where operator/e2e/journey tests live ("" = none)
    "test_command": "auto",                     // how to run the suite ("auto" = detect, "" = unknown)
    "test_timeout_sec": 600,                    // optional: kill a gate test run after this long
    "test_lock_wait_sec": 600,                  // optional: how long to wait for another session's run
    "agents_bundle": {                          // optional: default agent bundle for /harness:agents
      "repo": "octanelabsdev/rails-agents",     //   owner/name slug or git URL
      "glob": ["rails-*.md", "dhh-code-reviewer.md"] // which files in the bundle are agents
    }
  }
}
```

### Field semantics
- **`impl_dirs`** — a repo-relative path is "implementation" if it's under any of these. Drives
  *both* gates. Everything else (tests, config, docs, `.claude/`) is never gated.
- **`ui_dirs`** — a subset of the implementation surface whose change is expected to come with an
  operator-journey test. Leave `[]` for stacks with no UI layer.
- **`operator_test_dir`** — where journey/e2e tests live. If empty, the verification gate skips the
  operator-test check.
- **`test_command`** — the canonical check the verification gate **runs** on a Stop with impl changes;
  a non-zero exit blocks (see [components.md](components.md)). If empty, the gate only runs its
  advisory operator-test check. **`"auto"`** (the `rails` preset's default) picks the command for the
  configured `stack.name` on every run. For `rails`: `bundle exec rspec` when `spec/` exists and
  `rspec-rails` is in the bundle, otherwise `bin/rails test`. Any other value is run exactly as written,
  so an explicit `bin/ci` stays `bin/ci`. `"auto"` on a stack with no resolver blocks every Stop as a
  SETUP ERROR rather than skip the tests. `/harness:doctor` prints the command the gate will run and
  flags an explicit Rails command that doesn't match the repo's suite.
- **`test_timeout_sec`** / **`test_lock_wait_sec`** (optional, whole seconds, default 600 each) — the
  verification gate runs `test_command` under a repo-wide lock so concurrent sessions don't share the
  test database mid-run. The first kills a run that takes longer; the second is how long to wait for
  another session's run before blocking as UNVERIFIED. Both are trimmed to fit the Stop hook's 1800s
  timeout (see [components.md](components.md)).
- **`components`** — the toggleable hooks honor these. `session_banner`, `skill_nudge`, `context_warning` and
  `guardrails_gate` default to **on** unless set to `false` (the guardrails gate denies at most once per
  context, so it can't wedge a session); the gates (`verification_gate`, `pipeline_gate`, `review_gate`) default
  **off** when unconfigured. When on, the pipeline gate runs in **warn** mode, and the verification gate
  **blocks** on a `test_command` failure (opt down with `.claude/.verification-warn`). `review_gate`
  (also part of the verification-gate Stop hook, opt-in) additionally requires a **verified blind-review
  artifact** for the current diff — produced by the `blind-review` skill, checked by
  `tools/review_verify.sh`; same `.claude/.verification-warn` downgrade. (The `harness_bootstrap` hook
  has no toggle — it only acts when there's no config yet; see [components.md](components.md).)
- **`context_warning.window`** (optional) — the context window, in tokens, that the context warning
  scales its 75/85/95% steps to. `HARNESS_CONTEXT_WINDOW` in the environment overrides it, which suits
  a per-user model choice better than a committed file. Unset, it is 1M, every current Claude model's
  window. Values must be a plain positive integer (no leading
  zeros, at most nine digits); a non-numeric `HARNESS_CONTEXT_WINDOW` disables this lookup (see
  [components.md](components.md)).
- **`agents_bundle`** (optional) — the default agent bundle `/harness:agents` pulls when given no
  repo. `repo` is an `owner/name` slug or git URL; `glob` lists which files in the bundle are agents.
- **`mcp`** (optional) — MCP servers the installer writes to the project's committed `.mcp.json`, in
  `.mcp.json`'s own `{"name": {"command": …, "args": […]}}` shape. A server you already have at user
  scope is skipped, since a project entry would override it.
- **`mcp_user`** (optional) — one MCP server shared by every project at **user scope**, instead of a
  project entry. `name` is the server name, `bin` the executable, `args` its arguments, and
  `projects_file` the server's project list (relative to `$HOME`). The installer registers the app in
  `projects_file` and, if the server isn't configured yet, prints the `claude mcp add --scope user`
  line with an absolute path; `/harness:doctor` checks both. The `rails` preset uses this for
  rails-mcp-server.
- **`mcp_guides`** (optional) — framework guides the MCP server reads: `resources_dir` (relative to
  `$HOME`), the `download_cmd` that fetches them, and the `libs` to check. The installer nudges you
  to download any missing ones (`--mcp-download` fetches them).

Paths are directory prefixes, repo-relative — not globs. `app` matches `app/models/x.rb`.

## Stack presets

Presets live in [`stacks/`](https://github.com/octanelabsdev/harness/tree/main/stacks) and are the `stack` object above:

| Preset | impl_dirs | operator_test_dir | test_command |
|---|---|---|---|
| `rails` | app, lib, db/migrate | test/system | auto (`bundle exec rspec` or `bin/rails test`) |
| `node` | src, lib, app | e2e | npm test |
| `python` | src, app | tests/e2e | pytest |
| `go` | cmd, internal, pkg | e2e | go test ./... |
| `generic` | src, lib | (none) | (none) |

The installer merges your chosen preset (or custom answers) with your component choices into
`.claude/harness.json`.

## Custom stacks

Pick `custom` in the installer (or `--stack custom`) and answer the prompts, or hand-write the
`stack` object. To make your own reusable preset, drop a JSON file matching the schema's `stack`
object into `stacks/yourstack.json` and pass `--stack stacks/yourstack.json` (or a path anywhere).

Example — a Phoenix/Elixir profile:
```json
{
  "name": "phoenix",
  "impl_dirs": ["lib"],
  "ui_dirs": ["lib/my_app_web/live", "lib/my_app_web/controllers"],
  "test_dir": "test",
  "operator_test_dir": "test/my_app_web/live",
  "test_command": "mix test"
}
```

## Commit it

`.claude/harness.json` is meant to be **committed** so your whole team shares the same stack profile
and component choices. It contains no secrets and no machine paths — only your project's conventions.

## Session-local markers (written as you work)

The gates read/write small marker files under `.claude/` (all gitignored):
- `.claude/current-story.yaml` — the DoR-passing story YAML the pipeline gate lints (dor_lint exit 0 = pass; the verdict is computed, not a stamp).
- `.claude/.small-fix` — declares independent small work that bypasses the pipeline gate.
- `.claude/.pipeline-block` — promotes the pipeline gate from warn to **block** for this repo.
- `.claude/.verification-warn` — downgrades the verification gate from **block** to warn-only for this repo.
- `.claude/.review/current.json` — the blind-review findings artifact (written by the `blind-review` skill, verified by `tools/review_verify.sh`; required when `review_gate` is on).
