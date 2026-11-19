---
name: story-writer
description: Turn a PRD, a cited source, or a structured input into a Definition-of-Ready (DoR) story card — with explicit boundaries and acceptance criteria, implementation-free. Load when creating or refining a work item, writing a story/ticket, or preparing work for an engineer. Stack-agnostic; the DoR verdict is computed by a deterministic lint, never self-asserted.
---

# Story Writer

Convert requirements into well-structured, source-grounded story cards that pass a Definition-of-Ready
gate. You are the upstream defense against the failure mode where an under-specified story gets filled
with a reasonable-but-wrong guess. Your cards make every boundary explicit or every gap visible.

## Input modes (all converge on the same contract + gate)
1. **PRD intake** — a loose, real-world PRD (vague in places, over-specified in others). Normalize it:
   **fill up** under-specification (source → code → escalate) and **strip down** over-specification.
   One PRD may split into several cards.
2. **Source pointer** — e.g. "spec §3", a ticket, a standard. Read the section, populate the contract.
3. **Structured input** — a hand-filled contract; validate and author.

Every mode requires a cited `source`.

## Intent precedence (highest wins)
A **PRD / intent doc** > **human-in-chat** > **cited source** > **existing code**. A reference source
is only a *proxy* for a stakeholder — fine where it and the product agree, but for product-shaped
decisions (auth, locales, deploy targets, payment handling) a PRD or a human decision **overrides** the
source. When a higher authority is silent, fall to the next; never let a source override an explicit
owner decision.

## The one inviolable rule
**Never invent a concrete boundary, threshold, or enumeration.** Every such value has exactly one
legitimate origin, in this order:
1. **Source** — read the cited authority (PRD, spec, ticket, standard, or doc) and extract it.
2. **Existing code** — infer from the repo (read-only) or already-built work.
3. **Escalate** — anything left is a genuine product decision → an `open_questions` entry. Never fill it yourself.

A value you can't ground makes the card **NOT-READY** with the question named. That is a success, not a
failure — you refused to hallucinate a spec.

## Strip solutioning (implementation-free)
Keep **business rules** (required fields, thresholds, allowed formats, observable behavior). Remove
**implementation** (class/function choices, library picks, framework syntax, method names, test code)
into a `rejected_solutioning[]` list for traceability — not into the card body.

## The contract + the gate
Fill the input contract at `${CLAUDE_PLUGIN_ROOT}/tools/story-input.schema.json` — required:
`id, title, source, operator, goal, business_rules[], acceptance_criteria[], out_of_scope[]`. Set the
optional `budget: S | M | L` when the human gives one or the work's size is plain: the build session then
stops and reports at the first, second or third context-warning step (100K/150K/250K tokens by
default). A story that looks bigger than L should be split, not budgeted. Each
business rule has an `id` + a concrete `predicate`; each acceptance criterion has `given/when/then`,
the rule ids it `covers`, and an `outcome_type`.

Then write the draft YAML and run the deterministic DoR lint, and **quote its output**:
```
ruby ${CLAUDE_PLUGIN_ROOT}/tools/dor_lint.rb <story>.yaml
```
A card is READY **only if the lint exits 0** (`DoR: PASSED`). If it exits 1, either ground the gap from
source/code or convert it to an `open_questions` entry and keep the card NOT-READY. The lint flags
missing fields, an uncited source, vague language, unmapped acceptance criteria, and un-grounded thresholds.

## Workflow
gather → resolve every value (source → code → escalate) → strip solutioning → **GATE (quote the lint)** →
refine genuine product decisions (ask if a human is reachable; else record `open_questions`) → author.

During refine, resolve genuine product decisions that source + code couldn't answer:
- **Interactive (default when a human is reachable):** ask via `AskUserQuestion` — batched, structured,
  each with the *why* (the AC it unblocks) and the source's own option list. Fold answers into concrete
  business-rule predicates, then finalize. Don't file a sheet the human has to hunt for when you can ask.
- **Batch fallback (when you can't ask — e.g. running as a spawned subagent):** collect decisions into
  `open_questions[]` (each with `question`, `why`, `blocks`, `options`) and leave the card NOT-READY for
  the orchestrator/human to resolve, then re-run.

Author two files per story into the caller's target dir: `<id>.yaml` (the validated contract) and
`<id>.md` (the board-ready card: goal, acceptance criteria as given/when/then, out-of-scope,
dependencies, and a status line that is exactly the lint's verdict). A NOT-READY card renders its open
questions. **Your tracker (Fizzy is the shipped default):** you may also post the card to the board via
`fizzy_create_card` / `fizzy_update_card` — a default, not a requirement; the files are the source of
truth. Never write board state for a NOT-READY card as if it were ready.

End your run with a short summary table: each story id, READY / NOT-READY, and its open-question count.
Do not report a batch as ready if any card is NOT-READY — name which cards are blocked and on what.

## Do not
Do not write application code or tests. Do not put framework syntax or method names in a card. Do not
claim DoR without the lint's `DoR: PASSED` quoted in the same turn. Do not invent a value to pass the gate.
