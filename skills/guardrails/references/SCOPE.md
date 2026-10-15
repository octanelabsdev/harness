<!-- guardrails v1 | SCOPE playbook -->
You are here because you are about to: plan or delegate an implementation; add a new file, class, module, layer, base class, concern, adapter/interface, config key, flag, option, dependency, or table; handle a case nobody named; or report a change whose diff reaches beyond the ask.

The most common complaint about agent-written code is that it does too much: abstractions with one caller, options nobody asked for, layers "for later", files and docs that weren't requested. Each piece looks reasonable alone; together they make a change that is slower to review, harder to change, and wider than the ask.

Echo protocol: for each item write one line — `S<n>: PASS — <evidence>` | `S<n>: FAIL — <what's over>` | `S<n>: N/A — <reason>`. A FAIL is fixed by removing the excess or moving it to a proposal, not by justifying it after the fact.

- S1. Write the ask in one sentence, then the smallest change that satisfies it. Anything beyond that is an extra: list it under `PROPOSED (not built):` in your report. Extras are offered, not shipped.
- S2. Every new abstraction (class, module, concern, base class, adapter, interface, service layer) needs a second caller that exists TODAY, or a requirement you can quote. Neither? Inline it. Extracting duplicated code into a shared helper waits for the third real use — not one plus imagined ones.
- S3. No speculative generality: no parameters, options, config keys, flags, hooks, or extension points for cases nobody named; no handling for states that cannot occur here. (Real failure paths on I/O still follow CODE C13 — that is correctness, not scope.)
- S4. New dependency, gem/package, service, table, or column: name the existing code, stdlib, or framework feature that does the job, and why it doesn't. Can't name why? Use the existing one.
- S5. No unrequested artifacts: no new READMEs, docs, comment headers, example files, generators, or test helpers for a single test. Match the surrounding code's density.
- S6. Delegating? Put the S1 sentence and a "do not add" list in the sub-agent's prompt, and review the returned diff against S1–S5 before accepting it. Sub-agents over-build by default.
- S7. Before reporting, run `git diff --stat` and paste it. For every file and every new symbol, name the line of the ask it serves. Anything that serves none is reverted or split into its own proposal. Problems you noticed but didn't need to fix go to VERIFY V13, not into the diff.

--- reference ---

## What "too much" looks like
- A service object, a form object, and a concern for logic one controller action uses once.
- A configurable strategy/adapter interface with a single implementation.
- A feature flag, a setting, and a migration "so it's easy to change later" when nobody asked for it to change.
- Retry, caching, or background processing added to a path with no measured need (see RUNTIME).
- A refactor of neighboring code "while I was in there".
- A new doc or README describing the change.

## Senior judgment is subtraction
A senior engineer's instinct is to delete, not to add. The simple version is easier to review, easier to change when the second real use arrives, and that second use will tell you the right shape of the abstraction better than a guess today. When existing code is structurally poor and the ask doesn't require touching it, the senior move is a short proposal, not a bundled rewrite.

## When the ask itself is big
Large asks still have a smallest version. Build that, show it, and let the human choose the next step — phased work beats one large speculative diff.
