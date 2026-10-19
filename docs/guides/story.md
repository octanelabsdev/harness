# A story

For one feature or one bug with clear edges: something you could describe in a paragraph and finish in
a day or two. Bigger than that, or several pieces that only work together: use a
[cycle](client-cycle.md).

## Example: Trailhead shows the wrong tax total

A customer reports that a two-night booking shows tax for one night.

### 1. Decide (skip if you already know)

> **You:** What should I work on next?

`product-manager` reads the board's real signals (pinned, blocking, priority, age) and proposes the top
item. Here it's the tax bug, because it's pinned and two other cards wait on it.

### 2. Write it up

> **You:** Write this up as a story.

`story-writer` turns the report into a Definition-of-Ready card: what's in, what's out, acceptance
criteria. Where the report is silent, it asks instead of guessing:

> **Claude:** Is tax charged per night or per booking? The report doesn't say, and the code does both
> in different places.
>
> **You:** Per night, at the rate on the booking date.

**Answer these yourself.** An open question answered by a guess is how the wrong thing gets built
correctly. The card passes a deterministic lint and is recorded at `.claude/current-story.yaml`, which
is what unlocks the pipeline gate.

### 3. Build

> **You:** Build it.

Claude (through your agents, if the project has them) writes a failing test for the reported case,
then the fix. When the turn ends, the Stop gate runs your tests. Red keeps the turn going:

```text
VERIFICATION GATE — test_command failed: bin/rails test
BookingTest#test_two_night_tax: expected 24.0, got 12.0
```

Your job here is light: glance at the diff, answer questions.

### 4. Review

> **You:** Blind-review this.

The reviewer gets the diff and the project's rules, but not the story or the conversation, so it judges
the code on its own terms. Critical findings go back for a fix, then it reviews again. With
`review_gate` on, a turn can't end on a stale or failing review, and any edit after the review makes it
stale.

### 5. Commit

Tests green and review passed: commit. Committing doesn't make the review stale; editing does.

## Signs it should have been a cycle

- The story-writer keeps finding open questions that need a client's answer.
- One story turns into "and then we also need…" three times.
- You want someone outside the team to sign off on it before it ships.
