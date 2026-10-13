# Working with the harness

This page is the day-to-day loop: what you do, what the harness does at each step, and what stops a
turn from ending. The [components](components.md) page has the detail on each piece; this one strings
them together.

## Pick the right lane

| The work is… | Lane | What gates it |
|---|---|---|
| A one-line fix, a typo, a config tweak | **Small fix** — `touch .claude/.small-fix` | Stop gate (tests) |
| A single feature or bug with clear scope | **Story** — one Definition-of-Ready card | Pipeline gate, Stop gate, review |
| A multi-phase build, or anything a client signs off | **Cycle** — dated folder, phases, a human gate per phase | Everything, per phase — see [Cycles](cycles.md) (not yet released) |

Pick the lightest lane that fits. Ceremony that doesn't match the size of the change gets skipped, and
a skipped gate teaches everyone to skip gates.

## The story loop (shipped)

### 1. Session start
The **banner** reports what's actually configured: global ruleset, stack, components, agents. Read it
rather than trusting memory. The **skill nudge** tells the model to invoke `guardrails`,
`product-manager` and `story-writer` on its own when their triggers fire.

### 2. Decide what's next
Ask for the next item, or name one. The `product-manager` skill prioritizes from the board's real
signals (pinned, blocking, priority, age) and routes the top item to `story-writer`.

### 3. Get it ready
`story-writer` turns the requirement into a Definition-of-Ready card: boundaries, acceptance criteria,
out-of-scope, and `open_questions` for anything it would otherwise have to invent. A deterministic lint
(`dor_lint`) computes the verdict. The passing card is recorded at `.claude/current-story.yaml`.

### 4. Build
Before the first edit under `impl_dirs`, the **pipeline gate** checks for a passing story (or
`.small-fix`). It warns by default; `touch .claude/.pipeline-block` to make it block. The **guardrails**
skill loads its short checklists at the moments mistakes happen: before the first edit, after a failed
command, before claiming "done".

### 5. End of turn: the Stop gate
When a turn ends with implementation code changed, the **verification gate** runs your `test_command`
through the shared test lock:

- **green** → the turn ends;
- **red** → blocked; Claude keeps going and fixes it;
- **no answer** (lock busy, timed out, setup error) → blocked as `UNVERIFIED` / `SETUP ERROR`, never a
  silent pass. See [Test runs](components.md#test-runs-one-at-a-time).

It also nudges (never blocks) when UI changed without an operator-journey test.

### 6. Review
Load the `blind-review` skill. It hands your reviewer agent the diff and the rules, **not** the story or
the conversation, and records `.claude/.review/current.json` stamped with the diff's hash. With
`components.review_gate` on, the Stop gate refuses to end the turn until that artifact matches the
current tree and passes. Any edit after the review makes it stale; committing the reviewed work does not.

### 7. Ship
Commit once the tests are green and the review passes. Running the full CI suite by hand? Put it
through the same lock so it queues behind (or ahead of) any session's gate instead of colliding:
see [Running the suite by hand](components.md#test-runs-one-at-a-time).

!!! note "Planned: `ship_command`"
    A separate, slower ship-time check (e.g. `bin/ci` for Rails) that must be green before a commit or
    phase close, while the Stop gate keeps running the faster `test_command`.

## Several sessions at once

Two sessions in one repo (or in two worktrees of it) are fine for **tests**: the lock makes their suites
take turns. They are **not** fine for the story and review files, which are one per checkout. Give each
parallel stream of work its own worktree.

## When the gate blocks and you disagree

`touch .claude/.verification-warn` downgrades the Stop gate to warn-only for this checkout. It's an
explicit, visible decision by a human to accept the risk. It is not something to reach for because a
test is inconvenient.
