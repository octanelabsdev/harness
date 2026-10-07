<!-- guardrails v1 | VERIFY playbook | adapted from github.com/TheColliny/FableClaudeMDForOpus -->
You are here because you are about to write "done", "fixed", "works", "passing", "complete", "resolved", or "ready", or to run `git commit` / `gh pr create`.

Echo protocol: walk this checklist writing one line per item — `V<n>: PASS — <command> -> <last output line>` | `V<n>: FAIL — <command> -> <failing line>` | `V<n>: N/A — <one-line reason>`. A PASS without a quoted output line counts as FAIL; an N/A without a reason counts as FAIL. Every quoted output line must appear verbatim in a tool result earlier in THIS turn — quote it, never retype it. Do not write "done"/"fixed"/"works", or run `git commit`, while any line reads FAIL.

- V1. Fresh evidence: your V1 line quotes the PRIMARY verification command run AFTER the last edit and its output line. Output from before the last edit proves nothing.
- V2. Test summary line quoted verbatim (e.g. Minitest -> "24 runs, 61 assertions, 0 failures, 0 errors, 0 skips"; Jest -> "Tests: 12 passed, 12 total"; pytest -> "12 passed in 0.3s"; PHPUnit -> "OK (12 tests, 30 assertions)"). "0 tests"/"no tests found" is a FAIL of verification, not a pass. Every skip/pending explained in one sentence or investigated. No test suite? Write `V2: N/A — no test suite (<Glob you ran> -> 0 hits)` and V4's behavior probe becomes mandatory.
- V3. Failure-token scan on any verification output over ~30 lines: `grep -iE 'error|fail|warn|skip|traceback|exception'`; quote up to the first 10 hits with a one-word disposition each (benign/real), or state "failure-token scan: 0 hits". More than 10 hits -> the run is not clean; stop and investigate. Output piped? print `${PIPESTATUS[0]}` (zsh: `$pipestatus`) to read the producer's exit code, not the filter's.
- V4. "It compiles / boots" is gate 0, never completion evidence. After build/typecheck/boot passes, also run the tests or a behavior probe for the changed path and quote its result — unless the task's DONE-WHEN is the build itself.
- V5. Verifying via a binary, asset bundle, or running server? It was rebuilt/restarted in THIS turn, or you ran from source. Asset/JS/compiled change -> the running dev server was restarted or the asset/binary rebuilt. No rebuild/restart after the edit = the run proves nothing.
- V7. Multi-part request: quote the original request verbatim; mark every distinct deliverable VERIFIED (command) / EDITED-UNVERIFIED / NOT-DONE. Reporting NOT-DONE is acceptable; silently dropping it is not.
- V8. Scope audit: run `git diff --stat HEAD`; give a one-line justification per changed file tracing it to the goal. Unjustifiable file -> revert it or flag it. An empty stat after edits this task is itself a FAIL — find where the changes went.
- V10. Changed a test expectation or ran snapshot-update this task? Paste the old-vs-new quote and justification; absent from the transcript = FAIL.
- V11. Controller/handler/route/endpoint change: completion evidence is a pasted request + response (curl / an integration or request-test result with status code and relevant body) exercising the changed route, including one case the change was supposed to alter. "Listening on :3000" is never evidence.
- V12. Triviality waives nothing — one-liners have the highest surprise rate per line. Sole exemption: comment/doc-only changes, stated as "comment/doc-only change; behavior verification not applicable". Whitespace edits in indentation-significant files (.py, .yaml, .haml, .slim) are NOT exempt: paste a parse/compile check.
- V13. Out-of-scope findings: list every problem you surfaced this task that is outside its scope and not fixed. Each must already be filed — a tracker card (paste the card number) AND an entry in the project's out-of-scope backlog note with evidence, owner, and whether anything user-facing is affected today (no tracker -> the backlog entry alone counts). Filing is the default, done without asking; asking the user "should this get a card?" is a FAIL. Only the fix itself, or any data change, needs the user's decision. Unverified counts or impact are labelled UNVERIFIED on the card, never left off. Echo `V13: PASS — <finding> -> card #<n>` per finding, or `V13: N/A — no out-of-scope findings this task`.

Review-gate reminder: your global CLAUDE.md's Code Review Gate (the project's configured reviewer) is a SEPARATE blocking step. VERIFY passing is necessary but not sufficient — do not report "done" or commit until the reviewer has run (unless the user waived it).

--- reference ---

## You are about to type "should work", "should fix", "likely resolves", or "ought to now"
Exactly two legal forms replace every hedge:
(a) `Verified: <command> -> <result line>`
(b) `UNVERIFIED — to confirm, run: <command>`
There is no third option. Canonical status vocabulary, all reports: VERIFIED / UNVERIFIED / EDITED-UNVERIFIED / NOT-DONE / CANNOT-REPRODUCE.

## You are writing a final summary containing more than one claim
Emit the evidence table — one row per claim:
| claim | exact command | quoted result line | ran after last edit? |
|---|---|---|---|
Any row with "n" or an empty result cell: re-run first or demote the claim to UNVERIFIED. Claims without a row are forbidden in the summary.

## A test you just made pass shares literals with your fix
Grep your production diff for any literal that also appears in the test file (strings, magic numbers, fixture/factory ids). A match means the fix is test-shaped: implement the general behavior, or explicitly justify the coupling.

## You are about to mark a todo, plan step, or STATE entry complete
Mark it complete ONLY in a turn where its acceptance command's passing output appears. Edit landed but nothing ran = EDITED-UNVERIFIED, never complete.
