# A client project as a cycle

!!! note "Built, not yet released"
    Cycles are built and tested but not in a release yet. This guide describes how they work today.
    The [Cycles](../cycles.md) page is the reference; this page is the walkthrough.

For work a client sees or signs off, in phases. Each phase ends with you using the result and approving
it in your own terminal. Claude can't approve for you.

**Who does what:** you decide what gets built, read the briefs, use the result and approve it. Claude
decides how to build it, and the gates check its work every turn.

## Example: the Riverbend visitor guide

Jordan, who runs a small town's visitor office, wants a simple mobile-first guide: local businesses and
trails, a town history page, a map, and a QR code on signs around town. One town for now, maybe more
later. A proposal has gone out; some questions are still open.

## Once per client: set up

Keep the code and the work about the code in separate repos, side by side:

```
~/work/riverbend/
  riverbend-guide/     # the app: code only
  riverbend-meta/      # cycles, and optionally brand and strategy notes
    cycles/
```

Point the app at the meta repo in `.claude/harness.json`:

```jsonc
"cycles": {
  "dir": "../riverbend-meta/cycles",
  "mirror": "~/notes/riverbend/cycles",   // optional: a one-way copy to your notes vault
  "deny": ["Project Lantern"]             // optional: removed from client reports
}
```

Both repos need a first commit before a cycle can start: each phase records the commit it began at.

## 1. Start and shape

> **You:** Start a client cycle for the Riverbend guide. The proposal is in proposal.md.

Claude creates a dated folder (`riverbend-meta/cycles/2026-11-02-visitor-guide/`), then interviews you
**one question at a time**, each with a recommendation and alternatives. Expect it to ask whether parts
should be built at all, and to build a "not building" list.

Every answer becomes a dated line in `decisions.md`:

```text
- 2026-11-02 — One QR code per town, pointing at the home page. Why: with one town, per-town and
  shared are the same thing, and per-town comes free if more towns are added.
- 2026-11-02 — No logins in this contract. Why: an editor is a paid add-on; nothing here blocks it.
```

**Questions only the client can answer** stay open, with the default you're building against in the
meantime. Don't let them get decided by accident.

## 2. Plan

> **You:** Plan it.

You get `plan.md` and `roadmap.yaml`: the phases, what each depends on, and a **Done when** list for
each. For client work, expect a **rework phase** after the first version the client can use: matching
the spec isn't the same as being right.

**Read both yourself.** There's no approval step for the plan, so your read is the sign-off. To change
a decision, ask for it to be superseded; the old line stays and the new one says what replaced it.

Then commit the meta repo. Restoring an earlier phase later relies on its git history.

## 3. Each phase

### Brief

> **You:** Start phase 1 and write its brief.

`brief.md` lists what the phase builds, its **Done when** items, the evidence required, and what's not
in this phase. The review and the evidence are both checked against it, so read the Done when list
carefully: it's what you'll be approving.

### Stories

> **You:** Break phase 1 into stories.

Each story goes through `story-writer` as in [A story](story.md), and its open questions come to you.

### Build, one story at a time

> **You:** Build the next story.

The Stop gate runs the tests at the end of every turn. Commit each story when you're happy with it.
Commits don't hide anything from the review, because it's measured from where the phase began.

### Review

> **You:** Blind-review phase 1.

The reviewer sees everything changed since the phase began, plus the brief's Done when and "not in this
phase" lists. It also flags work outside the brief. Critical findings go back to the build, and any
edit means a fresh review.

### Evidence

> **You:** Collect and stamp the evidence for phase 1.

Every Done when item gets a status and a proof:

- **verified**: a test, or a file you can open;
- **failing**: it doesn't work yet;
- **could-not-verify**: it couldn't be checked, with the reason. Things waiting on the client, such as
  their hosting account, land here. That's honest, not a failure, and it never counts as passed.

The evidence also says how to open the app.

### Use it, then decide

Open the app as the evidence says and use it the way Jordan's visitors would: on a phone, from the QR
code. Then, **in your own terminal**, from the app repo:

```sh
H=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/harness/harness/*/ | sort -V | tail -1)
bash "${H%/}/tools/cycle_approve.sh"
```

It shows the brief, the code changed since the phase began, the review and the evidence, and asks
whether you used it. Then:

- **approve**: the phase is done;
- **revise** with a comment: Claude sees the comment and works on it, then presents again;
- **reject** with a comment: back to the brief.

Approve is only offered when the review passes and the evidence is complete and current. What you
approve is exactly what you were shown: if anything changes while you're deciding, approve is refused
and you run it again.

### Wrap up the phase

> **You:** Write the phase 1 reports and sync.

A client cycle gets two reports per phase: an internal one, and a client one with the `deny` list
removed. The client report stays with you until you decide to send it. Then commit the app and the meta
repo; the next phase won't start while reviewed work is uncommitted.

## Coming back to it

> **You:** Resume the cycle.

A new session reads the summary, decisions, plan and current brief, says where things stand, and
carries on. Nothing depends on remembering the last conversation.

## When the client changes something

- **During a phase:** choose revise with the change as your comment, or record a new decision if it
  changes the plan.
- **Out of scope** (Jordan asks for a calendar of events): add it to the "not building" list, or to a
  later cycle. Don't slip it into the current phase; the review flags work outside the brief.

## When it's done, and the next contract

> **You:** Close the cycle.

Claude writes the final summary and drafts the client update. A client cycle won't close until every
phase is approved and has both reports.

When Jordan signs for a second town, that's a **new cycle** on the same app repo: its own decisions,
phases and sign-off. The first cycle stays in the meta repo as the history of how the app got here.
