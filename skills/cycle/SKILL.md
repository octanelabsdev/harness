---
name: cycle
description: Run a multi-phase piece of work as a cycle — a dated folder (usually in a sibling meta repo) holding a living summary, locked decisions, a plan, and per-phase briefs, reviews, evidence and human approvals. Load when the user starts, shapes, plans, resumes or closes a cycle, says "continue the current phase", or asks for work big enough to need phases or client sign-off. Stack-agnostic.
---

# Cycle

A cycle keeps everything decided about a piece of work in files, so any session or agent can pick it
up, and so every phase ends with evidence and a human decision instead of a claim. The human owns what
gets built and whether it's right; you own how.

The deterministic parts are in `${CLAUDE_PLUGIN_ROOT}/tools/cycle.sh` (run it from the code repo).
Never hand-create what it creates, and never write a phase's `approval.json` — only the human does.

## Where things are
- The cycle folder is `<cycles.dir>/<YYYY-MM-DD>-<slug>/` (from `.claude/harness.json`; usually a sibling
  meta repo like `../acme-meta/cycles`, otherwise `.claude/cycles`). `cycle.sh path` prints it; if
  several cycles are open, commands ask you to name one.
- `summary.md` — **required, living.** Front matter holds `tier` and `status` (cycle.sh edits those).
  Keep its sections current: Status, Next action, Learnings, Gotchas, Could not decide.
- `decisions.md` — one dated line per locked decision with its reason. To change one, add a new line
  that says what it supersedes; never edit or delete the old line.
- `plan.md` and `roadmap.yaml` — optional, written by **plan**.
- `phases/<n>-<slug>/brief.md`, `review.json`, `evidence/`, `approval.json` — one folder per phase.

## Tiers
- `summary-only`: small work. Keep `summary.md` current; no phases.
- `standard`: phases, each with a brief, a blind review and a human decision.
- `client`: as standard, plus the client-facing report for each approved phase.
Match the ceremony to the work. If a tier feels wrong, say so and ask; don't silently skip steps.

## Commands
Pick the matching section. Each ends by updating `summary.md` (Status + Next action).

### start
`bash ${CLAUDE_PLUGIN_ROOT}/tools/cycle.sh start <slug> --tier <tier> [--from <file>]`. Ask for the
tier if the user didn't say. `--from` imports scope the user already wrote. Then go to **shape**.

### shape
An interview that turns intent into locked decisions. Before asking anything, read `scope.md` (if
any) and the code the work touches, so you only ask what they can't answer for you.
1. Ask **one question at a time** (AskUserQuestion when available). Lead with your recommendation and
   a one-line reason, then the alternatives.
2. Ask early whether this should be built at all, and what is explicitly **not** being built.
3. Each answer → a line in `decisions.md`: `- <date> — <decision>. Why: <reason>.`
4. If you would have to guess a product decision, stop and ask. Record anything still open under
   "Could not decide" in the summary.
5. Done when the open questions are answered or explicitly parked. Set Next action to **plan**.

### plan
Write `plan.md` (goal, in scope, NOT building, risks) and `roadmap.yaml`:
```yaml
phases:
  - id: 1-invoice-model
    title: Invoice model and totals
    done_when:
      - <observable outcome a test or a person can check>
    depends_on: []
```
Every phase gets done-when items someone can check without your word for it. If the first phase that
produces something usable isn't the last, add a rework phase after it: what matches the spec still
needs to be used before it's right. Stop for the human to agree the plan before any phase starts.

### Run a phase
1. `cycle.sh phase <slug>` creates the next phase folder (it refuses until the previous phase is
   approved). Fill `brief.md` from the roadmap: Builds, Done when, Evidence required, Not in this
   phase.
2. Build it. The Stop gate runs the tests; keep them green.
3. Review blind: run the `blind-review` skill, with one change: the review covers everything since the
   phase began, committed or not. Use `B=$(cycle.sh base)` as the review's `base`, stamp `diff_sha` with
   `review_verify.sh --emit-sha "$B"`, and give the reviewer `git diff "$B"` plus untracked files. Also
   give it the brief's **Done when** and **Not in this phase** lists, so it can flag work outside the
   brief. Never give it this conversation or your account of what you did. Copy the passing artifact
   to the phase: `cp .claude/.review/current.json <phase>/review.json`. A critical finding goes back to
   step 2. (A review measured from a later commit is refused at approval: it may not cover the phase.)
4. Gather evidence for each done-when item into `<phase>/evidence/manifest.json`:
   ```json
   {"open_app": "how to run or open what was built",
    "items": [{"done_when": "<the brief's exact wording>", "status": "verified", "proof": "test/x_test.rb:12"}]}
   ```
   `status` is `verified`, `could-not-verify` or `failing`. `proof` is a test reference or a file in
   `evidence/` (e.g. `evidence/totals.png`). If you couldn't check something, say `could-not-verify` and
   why; never count it as passed. Then `cycle.sh evidence stamp` ties it (and every
   `evidence/` file) to the current diff, and `cycle.sh evidence` must exit 0. Any later code edit
   makes both the review and the evidence stale. Once a phase is approved, leave its folder alone:
   changing its review or evidence turns the approval into `approve-unverified`.
5. Update `summary.md`, then tell the human the phase is ready and give them this to run **in their
   own terminal**, from the code repo: `bash ${CLAUDE_PLUGIN_ROOT}/tools/cycle_approve.sh`. You cannot
   run it, and you never create, edit or copy a phase's `approval.json` (a hook denies both).
6. `cycle.sh status` shows their decision. `revise` → the comment it shows is your next task, back to step 2. `approve` → commit the reviewed work exactly as reviewed (the next phase starts from the latest
   commit and refuses to start while anything is uncommitted), then the next phase. `reject` →
   back to the brief with them.

### resume
"Continue" / "pick up where we left off": `cycle.sh active`, then read `summary.md`, `decisions.md`,
`plan.md`, `roadmap.yaml` and the current phase's brief, in that order. Run `cycle.sh status`. State
in two lines where the cycle is and what you'll do next, then do it.

### close
When every phase is approved: write the final `summary.md` (what shipped, what didn't, learnings),
draft the release note or client update in `summary.md` under "Announcement", then `cycle.sh close`.
It refuses while a phase is unapproved; don't work around it.

### sync
`cycle.sh sync` mirrors the cycle to the vault (one way). The vault copy is never edited; change the
cycle in its own folder and sync again.

## Self-check before you hand back
- `summary.md` says where things stand and what's next, in words a new session can act on.
- Every decision you relied on is in `decisions.md`.
- You claimed nothing a test, a review artifact or a screenshot doesn't show.
