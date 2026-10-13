# harness

**A stack-agnostic engineering harness for Claude Code.** It turns Claude Code into a disciplined
teammate — enforcement hooks, guardrail playbooks, and a product-management delivery pipeline — and it
works for *any* stack because it's driven by a small per-project config. You **bring your own agents**;
the harness supplies the mechanism.

```sh
git clone https://github.com/octanelabsdev/harness ~/harness
~/harness/install.sh /path/to/your/project      # interactive: pick your stack + components
```

That's it. Restart Claude Code in your project and the harness is live. Full detail in
[Install](install.md).

## Why this exists

Left alone, an AI coding agent forgets the rules it was told, claims "done" without running anything,
edits the wrong file, and drifts from your conventions. A **harness** is the scaffolding that holds it to
a standard:

- a **SessionStart banner** that reports *environment-verified* state (not the model's memory),
- a **verification gate** that won't let a turn end claiming success without evidence,
- a **pipeline gate** that keeps feature work flowing through a Definition-of-Ready story,
- **guardrails** — short checklists the model reads at the exact moment a known mistake is about to happen,
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
[octanelabsdev/rails-agents](https://github.com/octanelabsdev/rails-agents) for Rails. See
[Bring-your-own agents](agents.md).

## Where to go next

<div class="grid cards" markdown>

-   **Install**

    Interactive or flag-driven; scopes, updating, uninstalling.

    [Read →](install.md)

-   **Concepts & architecture**

    The plugin + config split and the security model.

    [Read →](concepts.md)

-   **Working with the harness**

    The day-to-day loop, from picking work to shipping it.

    [Read →](workflow.md)

-   **Examples**

    Real gate output for everyday situations, and a client cycle walkthrough.

    [Read →](examples.md)

-   **Cycles** (not yet released)

    Multi-phase work with evidence and a human gate per phase.

    [Read →](cycles.md)

-   **Components**

    The hooks and skills in detail; warn → block.

    [Read →](components.md)

-   **Configuration**

    `.claude/harness.json`, components, stack profiles.

    [Read →](configuration.md)

-   **Bring-your-own agents**

    Adding, overriding, authoring; the rails-agents example.

    [Read →](agents.md)

-   **Troubleshooting & FAQ**

    Common fixes and answers.

    [Read →](troubleshooting.md)

</div>

## Requirements

Claude Code, plus `bash`, `git`, `jq`, and `python3`. (`ruby` if you use the story-writer's DoR lint.)
Licensed MIT.
