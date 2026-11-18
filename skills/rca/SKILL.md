---
name: rca
description: Write the post-feature RCA — what went wrong before it shipped, what caught it, the error class, the guard that prevents it, and what was claimed without verification. Load when a feature or fix is finished (merged, shipped, or handed off), after any correction from the user, and after fixing a bug. Every feature gets one, not only the ones that broke. Stack-agnostic.
---

# RCA

Every feature ends with a written RCA, including the ones that shipped cleanly: each still has a story
about what nearly went wrong and what caught it. Implementing and reviewing sub-agents are in scope too.
A green suite and a passed review are not the end of the task.

## Where it goes
The project's notes location, as your global CLAUDE.md names it (for example a vault folder
`<project>/RCA/<date>-<slug>.md`). None named? Ask once where RCAs live; never leave the RCA only in chat.

## The four questions
1. **What did I get wrong before it shipped, and what caught it?** Name the mechanism: a test, a review,
   a live query, a gate, the user. If the user caught it, that is the most important line.
2. **What class of error was it?** One instance is a mistake; a class is a rule. "I asserted a cause I
   had not read the code for" is a class. "I typed the wrong date" is not.
3. **What guard now makes recurrence impossible, or why is none possible?** Prefer a failing test, a
   gate, or a structural change over "be more careful". No guard exists? Say so; that is a finding.
4. **What did I claim that I had not verified?** Separately from bugs. Reasoning confidently from a
   schema, memory, or a partial read and being corrected by data is its own recurring class.

## Recurrence
Search earlier RCAs for the same class before writing. Found? Log the count. **The same class twice
means the fix is structural, not more care** — propose the structural fix in the RCA.

## After a correction from the user
Log the pattern the same day as a rule that prevents the category, not the instance.

## After a bug fix
Fold the autopsy into the RCA: why it happened, and what would prevent that category.

## Out-of-scope findings
Problems found but not fixed are filed per guardrails VERIFY V13 (card + backlog entry). The RCA lists
them by reference; it does not replace the filing.
