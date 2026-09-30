---
description: Check whether a newer Cleetus release tag is available and, on request, move this project's pin to it (then reload).
---

Consumers pin the harness marketplace to an immutable release tag, so a pinned machine does **not**
auto-update — a new release has to be moved to deliberately. This command does that check and move.

First, **check** (read-only — always run this first and show the result):

```
bash "${CLAUDE_PLUGIN_ROOT}/tools/harness_update.sh" $ARGUMENTS
```

It prints the installed version vs. the latest release tag. **Exit 0** = up to date (or offline);
**exit 10** = a newer tag is available.

If a newer tag is available and the user confirms they want it, **apply** the bump:

```
bash "${CLAUDE_PLUGIN_ROOT}/tools/harness_update.sh" --apply
```

Apply finds the settings.json that declares the `harness` marketplace (project scope first, then user
scope), rewrites its `source.ref` (and `sha`) to the latest tag, and prints the activation step. It does
**not** touch the machine cache and does **not** `remove`/re-add anything — the settings source is
authoritative, but a reload alone does not re-fetch the marketplace clone at the new tag.

**After --apply, the change is not live yet.** Tell the user to run, in order:

```
/plugin marketplace update harness
/reload-plugins
```

`/reload-plugins` on its own keeps loading the old version. Then re-run `/harness:update` (not the
old version's script path — it reads its own `plugin.json` and would keep reporting the old version)
to confirm it now reports up to date.

Notes to relay when relevant: the effective pin is **tag-level** (protect your release tags — the `sha`
is written but is not the enforced guarantee); if no settings file declares the marketplace, the tool
points at `install.sh` to (re)establish the pin.
