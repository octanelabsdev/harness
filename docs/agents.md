# Bring-your-own agents

The harness ships **no** agents. It's deliberately agnostic about who does the work — you supply the
specialists in your project's `.claude/agents/`. This is what makes the harness stack-neutral: a
Rust team brings Rust agents, a Rails team brings Rails agents, and the same hooks/guardrails/PM
pipeline wrap around all of them.

## Adding agents

Agents are Markdown files in `.claude/agents/` (Claude Code's native location). Drop yours in — as
committed files, or as symlinks to a shared bundle.

### The easy way: `/harness:agents`

```sh
/harness:agents                 # your stack's default bundle, symlinked (per-developer, gitignored)
/harness:agents --copy          # same bundle, copied in as committed files (whole team)
/harness:agents owner/repo      # a specific bundle (slug or git URL) instead of the stack default
/harness:agents --copy owner/repo
```

It clones the bundle into a per-machine cache (`${XDG_CACHE_HOME:-~/.cache}/harness/agent-bundles/`),
then symlinks (default, gitignored) or copies (`--copy`, committed) its agent files into
`.claude/agents/`. With no repo argument it reads the stack's **default bundle** from
`.claude/harness.json`; if the stack declares none, it tells you to pass one.

**Declaring a stack's default bundle.** A stack preset (and therefore the `stack` block in
`.claude/harness.json`) can carry an `agents_bundle`:
```jsonc
"agents_bundle": {
  "repo": "octanelabsdev/rails-agents",       // owner/name slug, or a full git URL
  "glob": ["rails-*.md", "dhh-code-reviewer.md"] // which files in the bundle are agents
}
```
The `rails` preset ships this. Presets with no `agents_bundle` require an explicit repo argument; an
explicit bundle with no known glob takes all `*.md` files.

### The manual way

Equivalent to what `/harness:agents` does, if you'd rather wire it yourself:
```sh
git clone https://github.com/octanelabsdev/rails-agents ~/rails-agents
cd /path/to/your/project && mkdir -p .claude/agents
for f in ~/rails-agents/rails-*.md ~/rails-agents/dhh-code-reviewer.md; do
  ln -sfn "$f" ".claude/agents/$(basename "$f")"
done
# keep the machine-local symlinks out of git (they point at your $HOME clone):
printf '%s\n' '.claude/agents/rails-*.md' '.claude/agents/dhh-code-reviewer.md' >> .claude/agents/.gitignore
```

Prefer committing real files (`--copy`) if you want the whole team to get identical agents without
cloning a bundle. Prefer gitignored symlinks (the default) if agents come from a per-developer clone
(never commit a `$HOME` path).

## How agents and the harness interact

- The harness's **hooks and skills fire regardless of which agents are present** — guardrails load
  by task, the gates read the stack profile, the banner counts whatever's in `.claude/agents/`.
- The **PM pipeline** (`product-manager` skill) routes ready work to "the right engineer" — that's
  one of *your* agents. It doesn't care what stack they are.
- If you also install an agent bundle *as a plugin*, note that **project `.claude/agents/` overrides
  same-named plugin agents** — your project's version wins.

## Authoring your own agents

An agent is a Markdown file with YAML front-matter:
```markdown
---
name: my-domain-expert
description: What this agent owns and when to use it.
model: sonnet
tools: Read, Write, Edit, Grep, Glob, Bash
---

# My Domain Expert
Instructions, conventions, and the discipline this agent follows…
```
Guidance:
- **One clear owner per domain.** Route each kind of work to the agent that owns it.
- **Ground the agent in truth, not memory.** If your stack has a way to query the real project
  (a language server, a schema/route introspector, an MCP server), instruct the agent to use it
  before inferring structure from partial reads.
- **A reviewer at the end.** Keep a review agent as the final gate before you call work done. If you run
  the **review gate** (`components.review_gate`), your reviewer must fit the blind-review contract below.

### The blind-review contract (for `review_gate`)

When `components.review_gate` is on, the `blind-review` skill drives your project's reviewer and the
verification gate verifies the result. Your reviewer (BYO — Rails ships `dhh-code-reviewer`) must:

- **Review blind.** It is given only the diff, the review rules, and access to ground truth — never the
  card, the conversation, or the intent behind the change (that framing is what makes a reviewer
  rationalize the mistake). It may still read the full files and query ground truth.
- **Emit structured findings** conforming to `${CLAUDE_PLUGIN_ROOT}/tools/review-findings.schema.json`:
  a `verdict` (`pass` | `changes-requested`) and `findings[]` with `file`, `line` (a line in the diff),
  `severity` (`critical` | `improvement`), `category`, `summary`, `failure_scenario`, and `evidence`.
  The `blind-review` skill records this to `.claude/.review/current.json`.
- **Cite real diff lines + concrete failure scenarios.** `tools/review_verify.sh` rejects the artifact
  if its `diff_sha` doesn't match the current tree or a finding cites a line not in the diff — so a
  hand-written green result can't satisfy the gate. State a clean `pass` plainly; don't invent findings.

A reviewer that doesn't emit the schema still works as a normal review agent; it just can't satisfy the
automated `review_gate` (which stays opt-in, default off).
- **Let the harness carry discipline.** You don't need to bake guardrails or verification rules into
  each agent — the guardrails skill and the gates handle that globally. Keep agents focused on their
  domain.

## Ground-truth tooling & the two "bookshelves"

Agents do better work grounded in truth than in memory. Two complementary, **stack-declared**
mechanisms — both wired by the installer, neither hard-coded to a `$HOME` path:

1. **A ground-truth MCP server** (what the app *is* — schema/routes/live code). A stack profile's
   `mcp` block is written to a committed `.mcp.json`. The rails preset instead uses one **user-scope**
   `rails` server (`mcp_user`) shared by every app: rails-mcp-server runs standalone and shells into
   each app's own `bin/rails`, so it never goes in the app's Gemfile. The installer registers the app in
   `~/.config/rails-mcp/projects.yml` and, if you don't have the server yet, prints the one-time
   `claude mcp add --scope user rails -- /absolute/path/to/rails-mcp-server --mode stdio` line.
   `/harness:doctor` flags a missing server, a missing registration, or a project `.mcp.json` entry
   that overrides it. Instruct your agents to query it before inferring structure from partial reads.

2. **Guide/reference bookshelves** (the *how/why*):
   - **MCP guide resources** — framework docs the server's `load_guide` reads. A stack's `mcp_guides`
     block lists the libraries (rails → rails/turbo/stimulus/kamal). These are a **machine-level,
     one-time download**: the installer checks `~/.config/rails-mcp/resources/` and nudges you to run
     `rails-mcp-server-download-resources <lib>` for any missing ones (or `--mcp-download` to fetch them).
   - **The EPUB bookshelf** — the `bookshelf` skill (`${CLAUDE_PLUGIN_ROOT}/tools/tome.sh`) reads your
     own reference books (never shipped — copyright). Point it at your shelf with **`TOMES_DIR`**, set
     once per machine/profile in your config home's `env` block (the installer's user step can write it).
     Agents quote the source line they rely on.

> These are *distinct*: the MCP server + guides cover the framework's current surface; the EPUB shelf
> covers deeper design/idiom references. Both are optional and BYO-populated.

### Pointing an agent at the bookshelf

To have an agent ground its convention/idiom calls in your reference books, give it the `Skill` tool
and drop this directive into the agent's body. It **fails gracefully** — an empty or unset shelf never
blocks the agent:

```markdown
---
name: my-domain-expert
description: What this agent owns and when to use it.
model: sonnet
tools: Read, Write, Edit, Grep, Glob, Bash, Skill   # Skill is required to invoke the bookshelf
---

# My Domain Expert
…

## Grounding conventions in primary sources
Before asserting a language/framework convention, an OO/refactoring call, a testing approach, or a
database behavior, consult the **bookshelf** skill and quote the source line you rely on:
invoke `harness:bookshelf` (or run `${CLAUDE_PLUGIN_ROOT}/tools/tome.sh`).
If the shelf is empty or the book isn't there, say so and fall back to the framework's live docs or an
explicit "unverified" label — never block on it and never invent a book's contents.
```

Notes:
- **`Skill` in `tools:` is required** for the agent to invoke a plugin skill; without it, the agent
  can still call the reader directly over Bash (`${CLAUDE_PLUGIN_ROOT}/tools/tome.sh`).
- The graceful-fallback line is not optional boilerplate — it's what keeps a missing/empty `TOMES_DIR`
  from turning grounding into a hard stop. `tome.sh` itself falls back to common shelves and reports a
  miss rather than erroring.

## The delegation map

Where you enforce "always delegate to an agent," put it in your global ruleset
(`templates/global-CLAUDE.md` has a `TODO` slot for the delegation map). The harness provides the
enforcement scaffolding; your ruleset + agents provide the routing.
