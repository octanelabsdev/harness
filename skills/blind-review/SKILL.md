---
name: blind-review
description: Produce a blind code review of the current diff and write the findings artifact the verification gate checks. Load before finishing a code change when the review gate is on (components.review_gate), or whenever you want an independent review of the working-tree diff. Stack-agnostic; the reviewer is BYO (your project's reviewer agent, e.g. Rails -> dhh-code-reviewer).
---

# Blind Review

Produce an independent, **blind** review of the CURRENT diff and record it as a findings artifact that
`verification_gate` verifies against that exact diff. Blindness is the point: the reviewer must not see
the card, the conversation, or the intent that produced the code — only the diff, the project's rules,
and the catalog of ways code fails. That is what stops a reviewer from rationalizing the very mistake
the task framing introduced.

## Why an artifact (and why you can't fake it)
A Stop hook can't spawn a reviewer, so the gate can't *run* the review — it verifies what you wrote.
`tools/review_verify.sh` refuses an artifact whose `diff_sha` doesn't match the current tree (measured
against the recorded `base` commit, so committing the reviewed work doesn't invalidate it), or whose
findings cite `file:line`s that aren't in the diff. So you cannot satisfy the gate by hand-writing a
green result: the review has to engage with the real changed lines, on the real current diff.

## Steps
1. **Pin the diff's identity.** From the repo root, run
   `bash ${CLAUDE_PLUGIN_ROOT}/tools/review_verify.sh --emit-sha` to get the canonical `diff_sha` for the
   current tree and `bash ${CLAUDE_PLUGIN_ROOT}/tools/review_verify.sh --emit-base` to get the `base`
   commit it is measured against, and capture the diff itself (`git diff HEAD` plus untracked files,
   excluding `.claude/`).
2. **Delegate to the configured reviewer, BLIND.** Spawn your project's reviewer agent (Rails ->
   `dhh-code-reviewer`) in a fresh context and hand it ONLY: the diff, the review rules / failure
   catalog, and the instruction to review blind. Do NOT pass the story, the card, the conversation, the
   plan, or what the change was "supposed" to do. Tell it explicitly: judge whether the change is
   correct on its own terms; every finding must cite `file:line` in the diff and a concrete failure
   scenario; state plainly when there are no critical issues.
3. **Write the artifact** to `.claude/.review/current.json`, conforming to
   `${CLAUDE_PLUGIN_ROOT}/tools/review-findings.schema.json`:
   - `diff_sha` and `base`: the values from step 1 (re-run both if you edited anything after
     reviewing). With `base` recorded, committing the reviewed changes keeps the artifact fresh; any
     further edit, committed or not, makes it stale.
   - `verdict`: `pass` (no critical findings) or `changes-requested`.
   - `findings[]`: each with `file`, `line` (a line in the diff), `severity` (`critical`|`improvement`),
     `category`, `summary`, `failure_scenario`, and `evidence` — for a structural claim, the ground-truth
     introspection you ran (e.g. `bin/rails runner`), never a partial-read guess.
4. **Verify locally.** `bash ${CLAUDE_PLUGIN_ROOT}/tools/review_verify.sh` — exit 0 = pass, 1 =
   changes-requested, 2 = stale/invalid. Exit 2 means your artifact doesn't match the current diff
   (you edited after reviewing) — re-review. Exit 1 means address the critical findings and re-review;
   don't paper over the gate with `.claude/.verification-warn` unless a human decides to accept the risk.

## Blindness — what to withhold vs allow
- **Withhold** (removes the framing that biases the verdict): the story/card, the PRD, the conversation,
  the plan, "what it should do."
- **Allow** (evidence, not framing): the diff, reading the full files, and ground-truth
  (schema/routes/associations via live introspection). Blindness removes bias, not evidence.

## Precision over recall
A review that flags everything trains people to ignore it. Every finding carries a concrete failure
scenario (inputs/state -> wrong outcome) and cites the line. If you can't name how it fails, it isn't a
critical finding. Say clearly when the change is clean — a `pass` with an empty `findings` list is a
valid, useful review.
