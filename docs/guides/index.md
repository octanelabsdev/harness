# Choosing a lane

Every piece of work goes through one of two lanes. Pick the lightest one that fits. Ceremony that
doesn't match the size of the change gets skipped, and a skipped gate teaches everyone to skip gates.

| If the work is… | Lane | Guide |
|---|---|---|
| A typo, a copy change, a config tweak, a one-line fix | **Small fix** | [A small fix](small-fix.md) |
| One feature or bug you could describe in a paragraph, done in a day or two | **Story** | [A story](story.md) |

Bigger than one story? Split it into stories, one per piece you could ship on its own.

## The tools, and when they come into play

**You ask for these:**

| Say… | Tool | When |
|---|---|---|
| "What should I work on next?" | `product-manager` | You sit down and don't know where to start |
| "Write this up as a story" | `story-writer` | Before building anything that isn't a small fix |
| "Blind-review this" | `blind-review` | A story is built and the tests are green |
| "Check the books on …" | `bookshelf` | A design or idiom call you'd like grounded in a source |
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
| Wednesday | Riverbend visitor guide | Add the events calendar | Story |
| Thursday | Riverbend visitor guide | The contact page lists the wrong opening hours | Small fix |
| Friday | Trailhead | Not sure what's next | "What should I work on next?" |
