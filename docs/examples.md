# Examples

Worked examples of the harness in use. Everything under **Shipped** shows real output from the hooks
and tools (only the test commands and host names are made up). Everything under **Planned** is an
illustration of the [cycle](cycles.md) design and will change as it's built.

## Shipped

### A small fix

You notice a typo in a model's error message.

> **You:** The invoice validation message says "ammount". Fix it.

```sh
touch .claude/.small-fix     # independent, obvious work: no story needed
```

Claude edits `app/models/invoice.rb`. The pipeline gate sees `.small-fix` and lets the edit through.
When the turn ends, the Stop gate still runs the tests, because a one-line change can break a test
like any other. Green, so the turn ends. Delete `.small-fix` when you're done so the next feature goes
through a story.

### A story, start to finish

> **You:** What should I work on next?

The `product-manager` skill reads the board and proposes the top item, here a card "Invoices show a
tax line", because it's pinned and blocks two others. It routes it to `story-writer`.

`story-writer` drafts a Definition-of-Ready card from the card and the existing code. Where the card is
silent it doesn't guess; it asks:

> **Claude:** The card doesn't say whether tax is per line or per invoice. That's a product decision.
> Which one?
>
> **You:** Per invoice, single rate from the account settings.

The DoR lint passes and the story is recorded at `.claude/current-story.yaml`. Claude builds it. At the
end of the turn the Stop gate runs `bin/rails test` and it's red:

```text
VERIFICATION GATE — test_command failed: bin/rails test
1 runs, 1 failures
InvoiceTest#test_total: expected 110.0, got 100.0
```

The turn doesn't end. Claude sees the failure, fixes the rounding, and the next Stop is green. Then:

> **You:** Run a blind review.

The `blind-review` skill gives your reviewer agent the diff and the rules, not the story or this
conversation, and writes `.claude/.review/current.json`. If you edit anything after that, the gate
(with `review_gate` on) refuses the stale review:

```text
VERIFICATION GATE — code review not satisfied for the current diff:
review: artifact is stale — it reviewed a different diff than the current tree (edit-after-review). Re-run the review.
```

Review again, get a `pass`, commit.

### Two sessions ending at the same time

You have two Claude sessions in the same repo, or in two worktrees of it. Both finish a turn within a
second of each other. Before, both suites hit the same test database at once and failed each other at
random. Now the second waits for the first:

```text
run_tests: another test run is in progress — waiting for it
```

…then runs once the first finishes and reports its own result. If the first holds the lock longer than
`test_lock_wait_sec`, the second doesn't pretend:

```text
VERIFICATION GATE — UNVERIFIED — another test run held the lock past 600s; tests did NOT run: bin/rails test
run_tests: BUSY — another test run has held the lock for 600s (22758 1791858710 900 mbp.local); not run
```

The owner line is the holder's pid, start time, timeout and host. End the turn again once the other
run finishes.

### A suite that's slower than its timeout

Your `bin/ci` takes about 11 minutes, longer than the default 600s:

```text
VERIFICATION GATE — UNVERIFIED — test_command exceeded 600s (stack.test_timeout_sec, capped to fit the 1800s hook timeout) and was killed: bin/ci
run_tests: TIMEOUT — 'bin/ci' exceeded 600s and was killed
```

The suite and everything it started were killed, and the turn is blocked rather than passing
silently. Fix it in `.claude/harness.json`:

```json
"stack": { "test_command": "bin/ci", "test_timeout_sec": 900 }
```

### A typo in the config

```json
"stack": { "test_command": "bin/rails test", "test_timeout_sec": "ten" }
```

```text
VERIFICATION GATE — SETUP ERROR — tests did NOT run (bad stack.test_timeout_sec / stack.test_lock_wait_sec, or the test lock can't be created; details below): bin/rails test
run_tests: --timeout/--wait must be whole seconds, got 'ten'
```

### Running CI by hand without colliding

You want a full `bin/ci` before you push, while a session might be ending a turn:

```sh
H=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/harness/harness/*/ | sort -V | tail -1)
bash "${H%/}/tools/run_tests.sh" --timeout 900 -- bin/ci
echo $?   # 0 green · 1 red · 2 setup · 3 busy · 4 timed out
```

Your run and the session's gate queue behind each other instead of sharing the database.

## Cycles (built, not yet released)

!!! warning "On the development branch"
    The tool output below (folder paths, evidence, the approval prompt, the client report) is real
    output from the cycle tools. The conversation and the app are illustrations.

### A client cycle: invoicing for Acme

**Start and shape.**

> **You:** Start a client cycle for Acme invoicing.

```text
$ cycle.sh start acme-invoicing --tier client
/Users/you/work/acme/acme-meta/cycles/2026-10-14-acme-invoicing
```

`shape` interviews you one question at a time, recommending an answer each time:

> **Claude:** Should invoices be editable after they're sent? I recommend **no**: void and reissue
> instead, so the client's books always match what was sent. Alternatives: editable until paid;
> editable with an audit log.
>
> **You:** No. Void and reissue.

Each answer is locked into `decisions.md`:

```markdown
- 2026-10-14 — Sent invoices are immutable; corrections are void + reissue. Why: client's books must
  match what was sent.
- 2026-10-14 — Tax is per invoice, one rate from account settings. Why: Acme has a single tax region.
- 2026-10-14 — NOT building: partial payments, multi-currency.
```

**Plan.** `plan` turns the decisions into phases, each with done-when criteria, plus a rework phase
after the first usable version:

```yaml
phases:
  - id: 1-invoice-model
    done_when:
      - An invoice with two lines and 10% tax totals correctly, rounded to the cent
      - A sent invoice can't be edited; voiding it creates a linked replacement
  - id: 2-send-and-pdf
    depends_on: [1-invoice-model]
    done_when:
      - The client receives the invoice email with a PDF that matches the screen
  - id: 3-rework-after-use
    depends_on: [2-send-and-pdf]
    done_when:
      - Changes from using phases 1–2 for real are made and re-verified
```

**One phase through the loop.** Phase 1 gets a brief, Claude builds it, the Stop gate runs the tests,
and the blind reviewer checks the diff against the done-when list. It finds one critical issue and one
piece of work outside the brief:

```text
critical     app/models/invoice.rb:42  Rounds each line before summing; 3 lines of 33.333 total 99.99, not 100.00
improvement  app/models/invoice.rb:58  Outside the brief: adds a discount field; discounts aren't in this phase
```

Claude fixes both, and the edit makes the old review stale, so it's re-run and passes. Then it records
the evidence and ties it to the diff:

```text
$ cycle.sh evidence stamp
stamped phases/1-invoice-model evidence against the current diff
$ cycle.sh evidence
matches the current diff
  ✔ verified          An invoice with two lines and 10% tax totals correctly, rounded to the cent  — test/models/invoice_test.rb:12
  ? could-not-verify  A sent invoice can't be edited; voiding it creates a linked replacement  — evidence/void.png
open the app: bin/dev, then http://localhost:3000/invoices/1
```

"Could not verify" is not "passed". Claude says the phase is ready and gives you the command; you run
it in your own terminal, open the app, try voiding an invoice, and find the replacement isn't linked:

```text
$ bash ~/.claude/plugins/cache/harness/harness/<version>/tools/cycle_approve.sh

━━ 2026-10-14-acme-invoicing · 1-invoice-model · tier: client

Builds:
  Invoice model with line items, tax per invoice, totals, void and reissue.

Code changed since the phase began at 3f2a91c "Start invoicing cycle" (2 days ago):
  6 files changed, 214 insertions(+), 3 deletions(-)
  commits since then:
    9b1e0d2 Invoice model, totals and tax
Review: pass

Evidence:
  matches the current diff
    ✔ verified          An invoice with two lines and 10% tax totals correctly, rounded to the cent  — test/models/invoice_test.rb:12
    ? could-not-verify  A sent invoice can't be edited; voiding it creates a linked replacement  — evidence/void.png
  open the app: bin/dev, then http://localhost:3000/invoices/1

Did you use it yourself (open the app / run it)? [y/N] y
approve / revise / reject? revise
What needs to change? (required) The replacement doesn't link back to the voided invoice.
Recorded: 1-invoice-model → revise
```

Claude sees it straight away:

```text
$ cycle.sh status
cycle:  2026-10-14-acme-invoicing  (…/acme-meta/cycles/2026-10-14-acme-invoicing)
tier:   client    status: building
phases:
  1-invoice-model              revise
    comment: The replacement doesn't link back to the voided invoice.
```

It fixes the link, re-reviews, re-stamps the evidence and asks again. This time you approve.
`approval.json` records your decision, your name, the time, the review verdict and hashes of the review
and evidence, with the earlier revise kept in its history. If Claude tries to run the approval tool or
write `approval.json` itself, the `cycle_guard` hook denies it.

**Report and close.** Approving a client-tier phase writes both reports and copies the cycle to your
vault. With `"deny": ["AcmeCorp"]` in the config, the client report reads:

```markdown
# Phase 1: invoice-model

Accepted 2026-10-14.

## What was delivered
Invoice model for ▇▇▇: line items, tax per invoice, totals, void and reissue.

## How it was checked
- An invoice with two lines and 10% tax totals correctly, rounded to the cent — verified
- A sent invoice can't be edited; voiding it creates a linked replacement — verified
```

When every phase is approved, Claude writes the final summary and a draft client update ("Invoicing is
live: invoices are locked once sent, and corrections go through void and reissue…"), and
`cycle.sh close` marks the cycle closed and copies it to the vault one last time. Root-cause notes
written automatically at close are [planned](cycles.md#standards-and-learning-planned).
