# Choosing a lane

Every piece of work goes through one of three lanes. Pick the lightest one that fits. Ceremony that
doesn't match the size of the change gets skipped, and a skipped gate teaches everyone to skip gates.

| If the work is… | Lane | Guide |
|---|---|---|
| A typo, a copy change, a config tweak, a one-line fix | **Small fix** | [A small fix](small-fix.md) |
| One feature or bug you could describe in a paragraph, done in a day or two | **Story** | [A story](story.md) |
| Several stories that only make sense together, with a plan, or work someone signs off phase by phase | **Cycle** | [A client project as a cycle](client-cycle.md) |

The short rule: **a story is one thing you'd ask for; a cycle is a project with a plan you'd sign off.**

## When to start a cycle

Start one when any of these is true:

- **A client will see it or sign off on it.** Use the `client` tier: every phase gets your approval and
  an internal and a client report.
- **It needs more than about three stories, and the order matters**, such as a data model before the
  screens that use it.
- **There are decisions you'll want to find again in a month**, like "why didn't we build accounts?"
  Without a cycle that answer lives in a chat transcript.
- **It spans several sessions or days.** A new session picks a cycle up from its files ("resume the
  cycle"), not from anyone's memory.

Don't start one for a single bug or a single feature. That's a story, and a cycle would only add
paperwork.

Inside a cycle, the tier sets how much ceremony applies:

| Tier | Use it for |
|---|---|
| `summary-only` | Small work that deserves a record, such as a production incident fix |
| `standard` | Internal features |
| `client` | Client work |

## The tools, and when they come into play

**You ask for these:**

| Say… | Tool | When |
|---|---|---|
| "What should I work on next?" | `product-manager` | You sit down and don't know where to start |
| "Write this up as a story" | `story-writer` | Before building anything that isn't a small fix |
| "Blind-review this" | `blind-review` | A story or phase is built and the tests are green |
| "Check the books on …" | `bookshelf` | A design or idiom call you'd like grounded in a source |
| "Start / resume / close the cycle" | `cycle` | Multi-phase or client work |
| `/harness:status`, `/harness:doctor` | commands | Something feels off: a gate didn't fire, a plugin didn't load |

**These run on their own; you only notice them:**

- **Session banner**: what's actually configured, at the start of every session.
- **Guardrails**: short checklists Claude loads before an edit, after a failure and before saying "done".
- **Pipeline gate**: warns (or blocks) when feature code changes without a ready story or a small-fix
  marker.
- **Stop gate**: runs your tests at the end of every turn that changed code. A red suite keeps the turn
  going.
- **Review gate** (if on): a turn can't end without a passing review of the current code.

**Your override:** `touch .claude/.verification-warn` turns the Stop gate into a warning for this
checkout. Use it when you knowingly accept a red suite, such as a flaky test against an outside
service. It's a human decision, never Claude's. Delete the file to turn the gate back on.

## A week, for example

| Day | Repo | Work | Lane |
|---|---|---|---|
| Monday | Trailhead (a booking app) | A customer reports a wrong tax total | Story: write it up, build, blind-review, commit |
| Tuesday | Trailhead | A typo in the footer | Small fix |
| Wednesday | Riverbend visitor guide (client work) | Continue the build | "Resume the cycle": the next story in the current phase |
| Thursday | Riverbend visitor guide | The client signs for a second town | A **new cycle** on the same repo: new decisions, phases and sign-off |
| Friday | Trailhead | Not sure what's next | "What should I work on next?" |
