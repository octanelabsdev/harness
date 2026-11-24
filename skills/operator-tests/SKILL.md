---
name: operator-tests
description: Write tests that prove the operator finished the task the code exists for, not just that the code ran. Load before writing, planning, or delegating tests for any user- or operator-facing change, and before calling such a feature done. Stack-agnostic.
---

# Operator-Task Tests

A test must first answer: **does the operator complete the task that justified this code?** Internal-state
assertions ("the controller assigns @x", "the model validates Y") prove the code ran. They are necessary,
not sufficient.

Before writing or delegating a test:

1. **Name the operator task in plain English.** "Admin on the Reviews page sees their invitations", not
   "GET index loads invitations".
2. **Name the observable outcome:** rendered content, a redirect, an email or job enqueued, a persisted
   side effect, an error shown. What the operator sees, or what changes in the world.
3. **Name the test as the user story.** `admin opens Invitations tab and sees the invitation form`, not
   `index assigns invitation`. The test name is the requirement.
4. **Assert that outcome** with the framework's outcome assertions (rendered text/selectors, redirects,
   sent mail, enqueued jobs, row-count changes, HTTP status and body). Internal-state checks supplement
   it; they never replace it.
5. **One walk-the-journey test per feature:** the operator's real sequence, visit -> click -> fill ->
   submit -> see the result, through a system/end-to-end/integration test where the stack has one.

Failure messages name the user-visible regression ("admin can no longer see pending invitations"), not
only expected/actual values.

## Read path vs write path
The common miss: the display is tested, the workflow is not. If an operator adds, edits, or deletes data,
each of those flows gets its own operator-task test.

## Done means the operator succeeded
"Tests pass" is not the completion signal for an operator-facing feature; code can be fully covered and
still unusable. The signal is operator-task verification: a system test where possible, a driven browser
or real request where not. Quote it per guardrails VERIFY.

## The QA report
When an operator-facing feature or phase is finished, run the project's black-box QA pass before you
call it done. Nobody has to ask for it. Drive the running dev or staging app as the operator, walk the
key journeys, and produce the project's QA report. Your global ruleset or the project's QA config names
the renderer and the output folder. Never hand-write a report the renderer is meant to produce, and
never run the pass against production data. Open the report when it is written, and put its path in
your done message.

No QA report tooling or config in the project? Say so, and offer to set it up. Do not skip the step
without a word.

## Delegating tests
Put steps 1-3 (task, outcome, test name) in the brief, and reject returned tests whose names describe
internals.
