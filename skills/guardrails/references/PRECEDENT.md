<!-- guardrails v1 | PRECEDENT playbook -->
You are here because you are about to: name existing code as the pattern to follow ("build it like X", "mirror Y's structure", "copy Z's approach"); or add new behavior to an existing code path in that code's style. In-place bug fixes that add no new structure are N/A.

Existing code shows what someone once did, not what the team does now or what current practice recommends. Commit activity doesn't settle it: legacy code gets patched, bumped, and kept alive for years without its design ever being revisited. Repeating a pattern without checking it carries its mistakes into new code with the authority of "the codebase does it this way."

Echo protocol: for each item write one line — `P<n>: PASS — <evidence>` | `P<n>: FAIL — <what's missing>` | `P<n>: N/A — <reason>`. A recommendation to follow or extend existing code without P1–P4 lines is not allowed — label it `PRECEDENT-UNVERIFIED` and present it as a candidate, not a decision.

- P1. Read its history and classify it. Run `git log --follow --format='%h %ad %an %s' --date=short -- <path>` and paste: created date, the last commit that changed its DESIGN (structure, interfaces, approach), and what the recent commits actually are. Patches, dependency bumps, renames, reformats, and keep-it-running fixes are maintenance — they do not make the design current. Check `git rev-parse --is-shallow-repository` first; `true` -> `HISTORY-UNVERIFIED`.
- P2. One example is not a convention. Count how many places in the repo follow this pattern, and find the most recent NEW feature work of the same kind (new code, not maintenance of old code). Paste both. If recent new work does it differently, the recent work is the house style.
- P3. Check it against current practice — regardless of age or activity. Compare the idioms it uses with (a) the stack's framework introspection and guides for the PINNED version (Rails: the rails MCP — `switch_project`, then its framework guides) and (b) the reference bookshelf (`bookshelf` skill, `$TOMES_DIR`) — quote the line you rely on. Write `PRECEDENT: <path> — current` or `— dated: <what current practice does differently>`. Scale depth to blast radius: copying it as a template for new work gets the full check; extending one method checks the idioms you are about to repeat. A source unavailable -> say which, and label `PRECEDENT-UNVERIFIED`.
- P4. Verify the mechanisms the pattern depends on actually work in THIS repo: how it is loaded, how it is scheduled, how its tests are discovered, whether CI runs them. One concrete check each (a runner/console probe, the CI config line, the loader source). A pattern that looks clean but whose jobs never schedule or whose specs never run fails here. (Same discipline as MECHANISM M1.)
- P5. State the verdict and its basis: `follow`, `adapt — <deviations>`, or `don't follow — <reason>`. History is evidence, never the verdict: old-and-busy code can be legacy on life support, and new code can fail P4. Dated code you only need to extend gets a proposal for the current idiom, not an unrequested rewrite (see SCOPE).

--- reference ---

## The case this prevents
A PRD review recommended building a new feature as an in-repo engine "following `engines/user_authentication`" — on the sole basis that the engine existed. The user's first instinct was an age rule: over a year old, don't copy it. The check showed it was 3 months old, one author, two commits — an age rule would have waved it through. P2 and P4 are what sank it: it was the only engine (not a convention), recent feature work used plain namespaces instead, the host's cron-scheduling task only scanned the host's `app/jobs` (so engine cron jobs would never be scheduled), and CI ran a fixed list of spec directories (so engine specs would never run).

## Why not an age threshold
The user then named the opposite failure: legacy code that is touched regularly just to keep it running looks "recent" by last-commit date while its design is a decade old. Age cuts both ways, so neither "old" nor "recently touched" is a verdict. What matters is when the design was last decided (P1), whether new work still decides it the same way (P2), and whether current guides and books agree (P3).

## Cheapest check first
P1 is one `git log`. P2 is one grep plus one `git log --since` over new files. P3 for a small extension is one guide lookup. P4 is usually one config line or one console probe. All of it costs less than the review comment that would otherwise catch it.
